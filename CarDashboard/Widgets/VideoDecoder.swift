import VideoToolbox
import CoreMedia
import SwiftUI

final class VideoDecoder: ObservableObject {
    @Published private(set) var currentFrame: CGImage?

    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let decodeQueue = DispatchQueue(label: "com.cardashboard.videodecoder")
    private let ciContext = CIContext()

    private var lastFrameTime = Date()
    private var stalenessTimer: Timer?

    init() {
        // If no frame has arrived for a couple seconds (broadcast stopped or dropped),
        // clear the frozen last image so the UI falls back to the "waiting" state.
        stalenessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.currentFrame != nil, Date().timeIntervalSince(self.lastFrameTime) > 2 {
                self.currentFrame = nil
            }
        }
    }

    deinit {
        stalenessTimer?.invalidate()
    }

    func configure(sps: Data, pps: Data) {
        decodeQueue.async { [weak self] in
            self?.buildFormatDescription(sps: sps, pps: pps)
        }
    }

    func decode(frameData: Data) {
        decodeQueue.async { [weak self] in
            self?.decodeOnQueue(frameData: frameData)
        }
    }

    private func buildFormatDescription(sps: Data, pps: Data) {
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)
        var newFormatDescription: CMVideoFormatDescription?

        let status = spsBytes.withUnsafeBufferPointer { spsPointer -> OSStatus in
            ppsBytes.withUnsafeBufferPointer { ppsPointer -> OSStatus in
                guard let spsBase = spsPointer.baseAddress, let ppsBase = ppsPointer.baseAddress else {
                    return kCMBlockBufferBadPointerParameterErr
                }
                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let parameterSetSizes: [Int] = [spsPointer.count, ppsPointer.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDescription
                )
            }
        }

        guard status == noErr, let newFormatDescription else { return }
        formatDescription = newFormatDescription
        recreateDecompressionSession()
    }

    private func recreateDecompressionSession() {
        guard let formatDescription else { return }
        if let existing = decompressionSession {
            VTDecompressionSessionInvalidate(existing)
            decompressionSession = nil
        }

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: videoDecoderOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        var session: VTDecompressionSession?
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        decompressionSession = session
    }

    private func decodeOnQueue(frameData: Data) {
        guard let formatDescription, let decompressionSession else { return }

        var blockBuffer: CMBlockBuffer?
        let dataPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: frameData.count)
        frameData.copyBytes(to: dataPointer, count: frameData.count)

        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: dataPointer,
            blockLength: frameData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frameData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else { return }

        var sampleBuffer: CMSampleBuffer?
        var sampleSizes = [frameData.count]
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { return }

        var flagsOut = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
    }

    fileprivate func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer?) {
        guard let pixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.currentFrame = cgImage
            self?.lastFrameTime = Date()
        }
    }
}

private func videoDecoderOutputCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr, let decompressionOutputRefCon else { return }
    let decoder = Unmanaged<VideoDecoder>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()
    decoder.handleDecodedFrame(imageBuffer)
}
