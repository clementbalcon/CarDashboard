import ReplayKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler {
    private let connection = MultipeerConnectionManager(role: .advertiser)
    private var compressionSession: VTCompressionSession?
    private var batteryTimer: Timer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        connection.start()

        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.sendBatteryStatus()
        }
        sendBatteryStatus()
    }

    override func broadcastFinished() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        if let compressionSession {
            VTCompressionSessionInvalidate(compressionSession)
        }
        compressionSession = nil
        connection.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if compressionSession == nil {
            setUpCompressionSession(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        }
        guard let compressionSession else { return }

        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    private func setUpCompressionSession(width: Int, height: Int) {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: broadcastCompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { return }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFNumber)
        // Cap the keyframe gap in *time* too, not just frame count: ReplayKit delivers
        // frames at a variable rate, so a pure frame-count cap can leave seconds between
        // keyframes when the screen is static. A 1s ceiling bounds recovery time after a
        // dropped inter-frame.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)

        compressionSession = session
    }

    fileprivate func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == noErr, let dataPointer else { return }
        let frameData = Data(bytes: dataPointer, count: length)

        let isKeyframe = Self.isKeyframe(sampleBuffer)

        // Re-send SPS/PPS with every keyframe (not just once) so an iPad that connects
        // after the broadcast has already started still receives the decoder config.
        if isKeyframe, let parameterSets = Self.extractParameterSets(from: formatDescription) {
            connection.send(.videoConfig(sps: parameterSets.sps, pps: parameterSets.pps))
        }

        // Keyframes reliable (decoder sync points), inter-frames unreliable (see
        // MultipeerConnectionManager.sendVideoFrame for the rationale).
        connection.sendVideoFrame(frameData, reliable: isKeyframe)
    }

    private static func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool else {
            return true // absence of NotSync means this is a sync (key) frame
        }
        return !notSync
    }

    private static func extractParameterSets(from formatDescription: CMFormatDescription) -> (sps: Data, pps: Data)? {
        var spsPointer: UnsafePointer<UInt8>?
        var spsSize = 0
        var spsCount = 0
        var ppsPointer: UnsafePointer<UInt8>?
        var ppsSize = 0
        var ppsCount = 0

        let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil
        )
        let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: nil
        )

        guard spsStatus == noErr, ppsStatus == noErr, let spsPointer, let ppsPointer else { return nil }
        return (Data(bytes: spsPointer, count: spsSize), Data(bytes: ppsPointer, count: ppsSize))
    }

    private func sendBatteryStatus() {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return }
        connection.send(.batteryStatus(
            level: device.batteryLevel,
            isCharging: device.batteryState == .charging || device.batteryState == .full
        ))
    }
}

private func broadcastCompressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer, let outputCallbackRefCon else { return }
    let handler = Unmanaged<SampleHandler>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    handler.handleEncodedFrame(sampleBuffer)
}
