import SwiftUI

struct BatteryIndicatorView: DashboardWidget {
    static let widgetTitle = "Batterie iPhone"
    static let widgetSystemImage = "battery.50"

    @EnvironmentObject private var connection: MultipeerConnectionManager

    var body: some View {
        WidgetCard(title: Self.widgetTitle, systemImage: Self.widgetSystemImage) {
            switch connection.connectionState {
            case .idle:
                Text("Inactif")
                    .foregroundStyle(.tertiary)
            case .searching:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Recherche de l'iPhone…")
                        .foregroundStyle(.tertiary)
                }
            case .connected:
                if let battery = connection.batteryStatus {
                    HStack(spacing: 8) {
                        Image(systemName: battery.isCharging ? "battery.100.bolt" : batterySymbolName(for: battery.level))
                        Text("\(Int((battery.level * 100).rounded()))%")
                            .font(.title2.weight(.semibold))
                    }
                } else {
                    Text("Connecté — en attente des données")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func batterySymbolName(for level: Float) -> String {
        switch level {
        case ..<0.25: return "battery.25"
        case ..<0.5: return "battery.50"
        case ..<0.75: return "battery.75"
        default: return "battery.100"
        }
    }
}
