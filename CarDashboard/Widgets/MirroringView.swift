import SwiftUI

/// Fixed narrow vertical column reserved for the iPhone (Waze) mirror stream.
/// Kept separate from the extensible widget grid since its 9:19.5 aspect ratio
/// is dictated by the iPhone's portrait screen, not by grid sizing.
///
/// The decoder is injected from the environment (owned by the app) rather than
/// held here: this view is rebuilt whenever the iPad rotates and DashboardView
/// swaps layouts, and a locally-owned decoder would lose its H.264 config on
/// every rotation.
struct MirroringView: View {
    @EnvironmentObject private var decoder: VideoDecoder
    @EnvironmentObject private var connection: MultipeerConnectionManager

    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var tick = 0

    var body: some View {
        WidgetCard(title: "Waze (iPhone)", systemImage: "iphone") {
            if let frame = decoder.currentFrame {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                waitingState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(poll) { _ in tick += 1 } // refresh the plain diagnostic counters
    }

    private var waitingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("En attente du flux")
                .foregroundStyle(.tertiary)
            Text("Lance le broadcast depuis l'iPhone")
                .font(.caption)
                .foregroundStyle(.quaternary)

            // Live diagnostics, so a stuck stream tells you *why* right here in the tile.
            VStack(spacing: 3) {
                diagLine("Paquets vidéo reçus", "\(connection.videoPacketsReceived)")
                diagLine("Config H.264", connection.videoConfigReceived ? "reçue" : "non reçue")
                diagLine("Images décodées", "\(decoder.decodedFrameCount)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private func diagLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Text(value).foregroundStyle(.primary)
        }
    }
}
