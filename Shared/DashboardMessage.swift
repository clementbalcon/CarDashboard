import Foundation

enum DashboardMessage: Codable, Equatable {
    case batteryStatus(level: Float, isCharging: Bool)
    case videoConfig(sps: Data, pps: Data)
    case location(latitude: Double, longitude: Double)
    /// Liveness ping from the companion so the iPad can tell a still-alive but idle
    /// connection apart from a silently-dead one (Multipeer is slow to notice the latter).
    case heartbeat
}
