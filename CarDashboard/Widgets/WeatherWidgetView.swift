import SwiftUI

struct WeatherWidgetView: DashboardWidget {
    static let widgetTitle = "Météo"
    static let widgetSystemImage = "cloud.sun"

    @EnvironmentObject private var connection: MultipeerConnectionManager
    @StateObject private var weather = WeatherObserver()

    var body: some View {
        WidgetCard(title: Self.widgetTitle, systemImage: Self.widgetSystemImage) {
            if let current = weather.current {
                content(current)
            } else if let errorMessage = weather.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.tertiary)
            } else if connection.deviceLocation == nil {
                Text("En attente de la position de l'iPhone…")
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if let location = connection.deviceLocation {
                weather.update(latitude: location.latitude, longitude: location.longitude)
            }
        }
        .onChange(of: connection.deviceLocation) { _, location in
            if let location {
                weather.update(latitude: location.latitude, longitude: location.longitude)
            }
        }
    }

    @ViewBuilder
    private func content(_ current: CurrentWeather) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: weatherSymbolName(for: current.weatherCode, isDay: current.isDay))
                .font(.system(size: 36))
                .symbolRenderingMode(.multicolor)
            Text("\(Int(current.temperature.rounded()))°")
                .font(.system(size: 40, weight: .semibold))
        }

        if !weather.upcomingHours.isEmpty {
            HStack(spacing: 16) {
                ForEach(weather.upcomingHours) { hour in
                    VStack(spacing: 4) {
                        Text(hour.date.formatted(.dateTime.hour()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: weatherSymbolName(for: hour.weatherCode, isDay: true))
                            .font(.body)
                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
