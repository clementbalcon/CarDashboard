import SwiftUI

struct DashboardView: View {
    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= geo.size.height {
                landscapeLayout(geo)
            } else {
                portraitLayout(geo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: Landscape — Waze pinned left (~half width), widgets stacked on the right.

    private func landscapeLayout(_ geo: GeometryProxy) -> some View {
        let gap = DashboardLayout.gridSpacing
        let contentHeight = geo.size.height - 2 * gap

        return HStack(spacing: gap) {
            MirroringView()
                .frame(width: geo.size.width * DashboardLayout.mirroringWidthFraction)
                .frame(maxHeight: .infinity)

            VStack(spacing: gap) {
                MusicWidgetView()
                    .frame(height: contentHeight * DashboardLayout.musicHeightFraction)
                WeatherWidgetView()
                    .frame(height: contentHeight * DashboardLayout.weatherHeightFraction)
                ContactsWidgetView()
                    .frame(maxHeight: .infinity)
                BatteryIndicatorView()
                    .frame(height: contentHeight * DashboardLayout.batteryHeightFraction)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(gap)
    }

    // MARK: Portrait — Waze pinned left at max height, widget column on the
    // right, battery as a slim full-width strip at the bottom.

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        let gap = DashboardLayout.gridSpacing
        let contentHeight = geo.size.height - 2 * gap
        let batteryHeight = contentHeight * DashboardLayout.portraitBatteryHeightFraction
        let topHeight = contentHeight - batteryHeight - gap
        let mirrorWidth = topHeight * DashboardLayout.mirroringAspectRatio

        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                MirroringView()
                    .frame(width: mirrorWidth)
                    .frame(maxHeight: .infinity)

                VStack(spacing: gap) {
                    MusicWidgetView()
                        .frame(height: topHeight * DashboardLayout.portraitMusicHeightFraction)
                    WeatherWidgetView()
                        .frame(height: topHeight * DashboardLayout.portraitWeatherHeightFraction)
                    ContactsWidgetView()
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: topHeight)

            BatteryIndicatorView()
                .frame(maxWidth: .infinity)
                .frame(height: batteryHeight)
        }
        .padding(gap)
    }
}

#Preview {
    DashboardView()
        .environmentObject(MultipeerConnectionManager(role: .browser))
        .environmentObject(VideoDecoder())
        .preferredColorScheme(.dark)
}
