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

    var body: some View {
        WidgetCard(title: "Waze (iPhone)", systemImage: "iphone") {
            if let frame = decoder.currentFrame {
                Image(decorative: frame, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("En attente du flux")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
