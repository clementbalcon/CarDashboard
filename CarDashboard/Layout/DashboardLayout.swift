import SwiftUI

enum DashboardLayout {
    static let mirroringAspectRatio: CGFloat = 9.0 / 19.5
    static let gridSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20

    /// Waze mirror occupies the left half of the screen.
    static let mirroringWidthFraction: CGFloat = 0.5

    /// Landscape — right column vertical split (fractions of the padded content height).
    /// Music dominates, weather is a slim band, calendar fills the remainder,
    /// battery is a compact strip at the bottom.
    static let musicHeightFraction: CGFloat = 0.48
    static let weatherHeightFraction: CGFloat = 0.24
    static let batteryHeightFraction: CGFloat = 0.10

    /// Portrait — Waze pinned left at max height, widgets in the right column,
    /// battery as a slim full-width strip at the bottom. The mirror width is
    /// derived from its height via `mirroringAspectRatio`, so every point of
    /// height given to the battery strip widens the widget column.
    static let portraitMusicHeightFraction: CGFloat = 0.43
    static let portraitWeatherHeightFraction: CGFloat = 0.28
    static let portraitBatteryHeightFraction: CGFloat = 0.06
}
