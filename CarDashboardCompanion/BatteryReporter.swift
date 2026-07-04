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

    private var refreshTimer: Timer?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryChanged), name: UIDevice.batteryStateDidChangeNotification, object: nil)

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 1000 // weather only needs coarse, ~city-block position
        locationManager.requestWhenInUseAuthorization()

        connection.start()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendBatteryStatus()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        sendBatteryStatus()
    }

    private func sendBatteryStatus() {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return }
        connection.send(.batteryStatus(level: device.batteryLevel, isCharging: device.batteryState == .charging || device.batteryState == .full))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.connection.send(.location(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
