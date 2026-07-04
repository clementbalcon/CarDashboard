import ReplayKit
import SwiftUI
import UIKit

struct CompanionView: View {
    @StateObject private var reporter = CompanionReporter()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.largeTitle)
                    .foregroundStyle(isConnected ? .green : .secondary)
                Text(statusText)
                    .font(.headline)
            }

            Spacer()

            VStack(spacing: 16) {
                broadcastButton
                wazeButton
            }
            .padding(.horizontal, 24)

            Text("Laisse cette app ouverte pour transmettre la batterie et ta position à l'iPad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private var isConnected: Bool {
        if case .connected = reporter.connection.connectionState { return true }
        return false
    }

    private var statusText: String {
        switch reporter.connection.connectionState {
        case .idle: return "Inactif"
        case .searching: return "Recherche de l'iPad…"
        case .connected(let name): return "Connecté à \(name)"
        }
    }

    private var broadcastButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.red.opacity(0.85))
            Label("Démarrer le broadcast", systemImage: "record.circle")
                .font(.headline)
                .foregroundStyle(.white)
                .allowsHitTesting(false)
            // The system picker view sits invisibly on top and receives the tap —
            // iOS only allows starting a broadcast through this system control.
            BroadcastPickerButton()
        }
        .frame(height: 60)
    }

    private var wazeButton: some View {
        Button {
            openWaze()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.blue.opacity(0.85))
                Label("Ouvrir Waze", systemImage: "map.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(height: 60)
        }
        .buttonStyle(.plain)
    }

    private func openWaze() {
        guard let wazeURL = URL(string: "waze://") else { return }
        if UIApplication.shared.canOpenURL(wazeURL) {
            UIApplication.shared.open(wazeURL)
        } else if let appStoreURL = URL(string: "https://apps.apple.com/app/id323229106") {
            UIApplication.shared.open(appStoreURL)
        }
    }
}

/// Wraps RPSystemBroadcastPickerView — the only way iOS allows an app to start a
/// ReplayKit broadcast. The extension is preselected so the picker goes straight to
/// the start dialog. The internal system button is stretched over the whole surface
/// and its icon hidden, so the styled SwiftUI label underneath acts as the button.
private struct BroadcastPickerButton: UIViewRepresentable {
    static let extensionBundleID = "com.clementbalcon.CarDashboardCompanion.BroadcastExtension"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = Self.extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        DispatchQueue.main.async {
            for case let button as UIButton in picker.subviews {
                button.frame = picker.bounds
                button.imageView?.alpha = 0
                button.setImage(nil, for: .normal)
            }
        }
    }
}

#Preview {
    CompanionView()
}
