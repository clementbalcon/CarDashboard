import Foundation

enum DashboardMessage: Codable, Equatable {
    case batteryStatus(level: Float, isCharging: Bool)
    case videoConfig(sps: Data, pps: Data)
    case location(latitude: Double, longitude: Double)
}
