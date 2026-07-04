import SwiftUI

struct HourlyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let weatherCode: Int
}

struct CurrentWeather {
    let temperature: Double
    let weatherCode: Int
    let isDay: Bool
}

func weatherSymbolName(for code: Int, isDay: Bool) -> String {
    switch code {
    case 0: return isDay ? "sun.max" : "moon.stars"
    case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
    case 3: return "cloud"
    case 45, 48: return "cloud.fog"
    case 51, 53, 55, 56, 57: return "cloud.drizzle"
    case 61, 63, 65, 66, 67: return "cloud.rain"
    case 71, 73, 75, 77, 85, 86: return "cloud.snow"
    case 80, 81, 82: return "cloud.heavyrain"
    case 95, 96, 99: return "cloud.bolt.rain"
    default: return "questionmark"
    }
}

/// Fetches weather from Open-Meteo for coordinates supplied from outside (the iPhone's
/// relayed GPS position). The iPad no longer has any location responsibility of its own.
@MainActor
final class WeatherObserver: ObservableObject {
    @Published private(set) var current: CurrentWeather?
    @Published private(set) var upcomingHours: [HourlyForecast] = []
    @Published private(set) var errorMessage: String?

    private var lastCoordinate: (latitude: Double, longitude: Double)?
    private var refreshTimer: Timer?

    init() {
        // Re-fetch periodically for the last known position so the forecast stays fresh
        // even when the car isn't moving and no new location arrives.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let coordinate = self.lastCoordinate else { return }
                await self.fetchWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    /// Called whenever the iPhone reports a new position. Skips the network round-trip if
    /// the position hasn't meaningfully moved since the last successful fetch.
    func update(latitude: Double, longitude: Double) {
        if let last = lastCoordinate,
           abs(last.latitude - latitude) < 0.02, abs(last.longitude - longitude) < 0.02,
           current != nil {
            return
        }
        Task { await fetchWeather(latitude: latitude, longitude: longitude) }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]

        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            current = CurrentWeather(
                temperature: response.current.temperature2m,
                weatherCode: response.current.weatherCode,
                isDay: response.current.isDay == 1
            )
            upcomingHours = Self.parseUpcomingHours(response.hourly)
            errorMessage = nil
            lastCoordinate = (latitude, longitude)
        } catch {
            errorMessage = "Météo indisponible"
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    private static func parseUpcomingHours(_ hourly: OpenMeteoResponse.Hourly) -> [HourlyForecast] {
        let now = Date()
        var result: [HourlyForecast] = []
        for (index, timeString) in hourly.time.enumerated() {
            guard let date = hourFormatter.date(from: timeString), date >= now else { continue }
            guard index < hourly.temperature2m.count, index < hourly.weatherCode.count else { continue }
            result.append(HourlyForecast(date: date, temperature: hourly.temperature2m[index], weatherCode: hourly.weatherCode[index]))
            if result.count == 6 { break }
        }
        return result
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let isDay: Int
        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let weatherCode: [Int]
        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
    let current: Current
    let hourly: Hourly
}
