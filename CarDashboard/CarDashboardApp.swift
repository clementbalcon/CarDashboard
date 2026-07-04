import SwiftUI
import UIKit

@main
struct CarDashboardApp: App {
    @StateObject private var peerConnection = MultipeerConnectionManager(role: .browser)
    @StateObject private var videoDecoder = VideoDecoder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(peerConnection)
                .environmentObject(videoDecoder)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    // Wire the video pipeline once, at a level that survives iPad rotation.
                    peerConnection.onVideoFrame = { data in
                        videoDecoder.decode(frameData: data)
                    }
                    peerConnection.onVideoConfig = { sps, pps in
                        videoDecoder.configure(sps: sps, pps: pps)
                    }
                    peerConnection.start()

                    // Mounted on the dashboard, the iPad must never auto-lock — a locked
                    // screen looks exactly like "the connection died" to the driver.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}

/// Gates the dashboard behind a startup/diagnostic screen so connection problems are visible
/// (and self-diagnosing) instead of showing as silent "en attente…" widgets. Enters the
/// dashboard automatically once the essential link is up, or on demand.
struct RootView: View {
    @EnvironmentObject private var connection: MultipeerConnectionManager
    @State private var entered = false

    var body: some View {
        if entered {
            DashboardView()
        } else {
            ConnectionDiagnosticView(onEnter: { entered = true })
        }
    }
}

private enum DiagStatus {
    case ok, waiting, off
    var color: Color {
        switch self {
        case .ok: return .green
        case .waiting: return .orange
        case .off: return .gray
        }
    }
}

struct ConnectionDiagnosticView: View {
    @EnvironmentObject private var connection: MultipeerConnectionManager
    @EnvironmentObject private var decoder: VideoDecoder
    let onEnter: () -> Void

    // Re-reads the plain diagnostic counters on a cadence, and drives auto-enter.
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var tick = 0
    @State private var readySince: Date?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "car.side")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("CarDashboard")
                    .font(.largeTitle.weight(.bold))
                Text("Démarrage — vérification de la liaison iPhone")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                row("Connexion iPhone", isConnected ? .ok : .waiting, connectionDetail)
                Divider().overlay(Color.white.opacity(0.1))
                row("Batterie iPhone", connection.batteryStatus != nil ? .ok : .waiting, batteryDetail)
                Divider().overlay(Color.white.opacity(0.1))
                row("Position GPS", connection.deviceLocation != nil ? .ok : .waiting, locationDetail)
                Divider().overlay(Color.white.opacity(0.1))
                row("Config vidéo (H.264)", connection.videoConfigReceived ? .ok : .off, connection.videoConfigReceived ? "reçue" : "après broadcast")
                Divider().overlay(Color.white.opacity(0.1))
                row("Flux vidéo Waze", videoStatus, videoDetail)
            }
            .padding(20)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 520)

            Text("La batterie, la position et la météo s'activent seules. Le flux Waze n'arrive qu'après avoir lancé le broadcast depuis l'iPhone.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button(action: onEnter) {
                Text("Entrer dans le dashboard  →")
                    .font(.headline)
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onReceive(poll) { _ in
            tick += 1 // force a re-read of the plain (non-published) counters
            let ready = isConnected && connection.batteryStatus != nil
            if ready {
                if let since = readySince {
                    if Date().timeIntervalSince(since) > 2 { onEnter() }
                } else {
                    readySince = Date()
                }
            } else {
                readySince = nil
            }
        }
    }

    private func row(_ title: String, _ status: DiagStatus, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Circle().fill(status.color).frame(width: 13, height: 13)
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var isConnected: Bool {
        if case .connected = connection.connectionState { return true }
        return false
    }

    private var connectionDetail: String {
        switch connection.connectionState {
        case .idle: return "inactif"
        case .searching: return "recherche…"
        case .connected(let name): return name
        }
    }

    private var batteryDetail: String {
        guard let b = connection.batteryStatus else { return "en attente" }
        return "\(Int((b.level * 100).rounded()))%"
    }

    private var locationDetail: String {
        connection.deviceLocation != nil ? "reçue" : "en attente (repli iPad actif)"
    }

    private var videoStatus: DiagStatus {
        if decoder.currentFrame != nil { return .ok }
        return connection.videoPacketsReceived > 0 ? .waiting : .off
    }

    private var videoDetail: String {
        let n = connection.videoPacketsReceived
        if decoder.currentFrame != nil { return "\(n) paquets reçus" }
        if n > 0 { return "\(n) paquets, décodage…" }
        return "aucun paquet"
    }
}
