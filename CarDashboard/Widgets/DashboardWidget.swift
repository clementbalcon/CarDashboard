import SwiftUI

/// Conformance contract for every tile that appears in the widget grid
/// (mirroring excluded — it's laid out separately as a fixed narrow column).
/// New widgets only need to conform and be added to `DashboardView`'s grid.
protocol DashboardWidget: View {
    static var widgetTitle: String { get }
    static var widgetSystemImage: String { get }
}

struct WidgetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
        // Backstop: keep any oversized content contained within the card so a widget
        // can never bleed past its tile and off the screen edge.
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
    }
}
