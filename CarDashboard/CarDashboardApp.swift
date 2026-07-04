import SwiftUI

@main
struct CarDashboardApp: App {
    @StateObject private var peerConnection = MultipeerConnectionManager(role: .browser)
    @StateObject private var videoDecoder = VideoDecoder()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(peerConnection)
                .environmentObject(videoDecoder)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    // Wire the video pipeline once, at a level that survives iPad
                    // rotation. DashboardView rebuilds its layout subtree when the
                    // orientation flips, so a decoder owned by MirroringView would be
                    // torn down and recreated on every rotation — losing its H.264
                    // config until the next keyframe. Owning it here keeps it alive.
                    peerConnection.onVideoFrame = { data in
                        videoDecoder.decode(frameData: data)
                    }
                    peerConnection.onVideoConfig = { sps, pps in
                        videoDecoder.configure(sps: sps, pps: pps)
                    }
                    peerConnection.start()
                }
        }
    }
}
