import CoreLocation
import UIKit
import SwiftUI

/// Runs on the iPhone (companion app) and feeds the iPad over Multipeer:
///   - battery level (polled + on change),
///   - GPS position (the iPhone has real GPS; the car iPad often doesn't), which the
///     iPad uses to fetch local weather.
@MainActor
final class CompanionReporter: NSObject, ObservableObject, CLLocationManagerDelegate {
    let connection = MultipeerConnectionManager(role: .advertiser)

    // Emit-side diagnostics, shown on the companion's startup screen.
    @Published private(set) var lastBatterySentAt: Date?
    @Published private(set) var lastLocationSentAt: Date?
    @Published private(set) var locationAuthorized = false
    @Published private(set) var heartbeatsSent = 0

    private var refreshTimer: Timer?
    private var heartbeatTimer: Timer?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged), name: UIDevice.batteryStateDidChangeNotification, object: nil)

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 1000 // weather only needs coarse, ~city-block position
        // Keep feeding the iPad while the user is driving with Waze in the foreground: the
        // location background mode keeps this app alive so battery/heartbeat/GPS keep flowing.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestWhenInUseAuthorization()

        connection.start()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendBatteryStatus()
            }
        }
        // Frequent, tiny liveness ping so the iPad can tell "idle but alive" from "dead".
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.connection.send(.heartbeat)
                self.heartbeatsSent += 1
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        heartbeatTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        sendBatteryStatus()
    }

    private func sendBatteryStatus() {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return }
        connection.send(.batteryStatus(level: device.batteryLevel, isCharging: device.batteryState == .charging || device.batteryState == .full))
        lastBatterySentAt = Date()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationAuthorized = true
                manager.startUpdatingLocation()
            default:
                self.locationAuthorized = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.connection.send(.location(latitude: coordinate.latitude, longitude: coordinate.longitude))
            self.lastLocationSentAt = Date()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
