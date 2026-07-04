import MultipeerConnectivity
import SwiftUI

enum PeerRole {
    case advertiser
    case browser
}

struct BatteryStatus: Equatable {
    let level: Float
    let isCharging: Bool
}

struct DeviceLocation: Equatable {
    let latitude: Double
    let longitude: Double
}

/// Not @MainActor on purpose: this type is instantiated both from SwiftUI (main thread)
/// and from RPBroadcastSampleHandler (a non-actor-isolated ReplayKit class), so @Published
/// mutations are dispatched to the main thread manually instead of relying on actor isolation.
final class MultipeerConnectionManager: NSObject, ObservableObject {
    static let serviceType = "cardashboard"

    /// How long the browser tolerates silence on a "connected" session before deciding it's
    /// a zombie and forcing a fresh reconnect. Kept a few heartbeats wide to avoid flapping.
    private static let livenessTimeout: TimeInterval = 12
    /// How long to let discovery run without any connection before assuming the browser is
    /// wedged. Wide enough that the normal connect handshake is never interrupted.
    private static let searchGrace: TimeInterval = 20
    /// Minimum gap between two discovery restarts, so bursts of disconnect events (or a
    /// watchdog firing next to a delegate callback) don't thrash the radio.
    private static let restartDebounce: TimeInterval = 6

    enum ConnectionState {
        case idle
        case searching
        case connected(peerName: String)
    }

    private enum PacketTag: UInt8 {
        case controlMessage = 1
        case videoFrame = 2
    }

    @Published private(set) var connectionState: ConnectionState = .idle

    /// The last battery reading received, kept in its own slot so it survives (and isn't
    /// clobbered by) the video-config messages that flow on the same control channel.
    @Published private(set) var batteryStatus: BatteryStatus?

    /// The iPhone's last reported GPS position, relayed by the companion app. The iPad
    /// (often Wi-Fi-only in the car) uses this instead of its own location for weather.
    @Published private(set) var deviceLocation: DeviceLocation?

    /// Plain diagnostics for the startup screen (read from the main thread, written from the
    /// network thread — racy on purpose, exact counts don't matter for a status display).
    private(set) var videoConfigReceived = false
    private(set) var videoPacketsReceived = 0
    private(set) var heartbeatsReceived = 0

    /// Bypasses @Published on purpose: video frames can arrive up to 30x/sec and a decoder
    /// consumes them directly, so routing them through SwiftUI diffing would be wasteful.
    var onVideoFrame: ((Data) -> Void)?

    /// Delivered off the network thread whenever the sender re-announces its H.264
    /// parameter sets (SPS/PPS), i.e. on every keyframe. Routed to the decoder directly
    /// rather than through a shared @Published slot so it never contends with battery updates.
    var onVideoConfig: ((_ sps: Data, _ pps: Data) -> Void)?

    private let role: PeerRole
    private let myPeerID: MCPeerID
    private lazy var session: MCSession = {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        return session
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Display-name suffix marking the broadcast extension's peer (the video source). When
    /// present, the iPad prefers it over the companion — the device pair holds only one link.
    private static let extensionMarker = "écran"

    private var isRunning = false
    private var lastReceivedAt = Date()
    private var lastRestartAt = Date.distantPast
    private var watchdogTimer: Timer?
    private var knownPeers: Set<MCPeerID> = []

    /// `displaySuffix` distinguishes peers that share a device. The companion app and the
    /// broadcast extension both advertise from the same iPhone; without distinct display
    /// names the iPad's browser can fail to tell them apart and connect to only one — which
    /// is exactly why battery (companion) can work while video (extension) never arrives.
    init(role: PeerRole, displaySuffix: String? = nil) {
        self.role = role
        let base = UIDevice.current.name
        let name = displaySuffix.map { "\(base) · \($0)" } ?? base
        self.myPeerID = MCPeerID(displayName: String(name.prefix(63)))
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        connectionState = .searching
        startDiscovery()

        // Only the browser (iPad) watches liveness: the advertisers mostly send and would
        // otherwise flag their own — legitimately quiet — receive side as dead.
        if role == .browser {
            lastReceivedAt = Date()
            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.checkLiveness()
            }
        }
    }

    func stop() {
        isRunning = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()
        connectionState = .idle
    }

    func send(_ message: DashboardMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            var packet = Data([PacketTag.controlMessage.rawValue])
            packet.append(try JSONEncoder().encode(message))
            try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("MultipeerConnectionManager send error: \(error)")
        }
    }

    /// Hybrid reliability. Sending *every* frame reliably means one delayed frame
    /// head-of-line-blocks all the frames behind it on a congested link (the iPhone
    /// hotspot), which stalls the stream in bursts. Instead:
    ///   - keyframes (large, and every later frame depends on them) go reliable, so
    ///     the decoder always has a valid sync point;
    ///   - inter-frames go unreliable — a dropped one causes a brief artifact until
    ///     the next frame, not a stall, keeping latency low and the stream smooth.
    func sendVideoFrame(_ frameData: Data, reliable: Bool) {
        guard !session.connectedPeers.isEmpty else { return }
        var packet = Data([PacketTag.videoFrame.rawValue])
        packet.append(frameData)
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            print("MultipeerConnectionManager sendVideoFrame error: \(error)")
        }
    }

    // MARK: - Discovery lifecycle

    private func startDiscovery() {
        switch role {
        case .advertiser:
            let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        case .browser:
            let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
    }

    /// Tear down and recreate the advertiser/browser. MCNearbyService objects can get wedged
    /// after a drop and stop (re)discovering peers; recreating them forces a clean restart.
    ///
    /// Deliberately only driven by the watchdog, never reactively from a connection-state
    /// callback: recreating discovery objects *during* the connect handshake aborts it, and
    /// the iPhone exposes two same-named peers (companion app + broadcast extension) whose
    /// handshakes overlap — tearing down mid-flight leaves a connected-but-dead session.
    private func restartDiscovery() {
        guard isRunning else { return }
        guard Date().timeIntervalSince(lastRestartAt) > Self.restartDebounce else { return }
        lastRestartAt = Date()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        knownPeers.removeAll()
        startDiscovery()
    }

    /// The iPad keeps only one connection to the iPhone at a time, so pick the best peer: the
    /// broadcast extension (video) when it's available, otherwise the companion (battery/GPS).
    /// Switching requires dropping the current link first — the device pair won't hold two.
    private func connectToBest() {
        guard isRunning, let browser else { return }
        let ext = knownPeers.first { $0.displayName.hasSuffix(Self.extensionMarker) }
        let companion = knownPeers.first { !$0.displayName.hasSuffix(Self.extensionMarker) }
        guard let target = ext ?? companion else { return }
        if session.connectedPeers.contains(target) { return }

        if session.connectedPeers.isEmpty {
            browser.invitePeer(target, to: session, withContext: nil, timeout: 10)
        } else {
            // The wrong peer is connected (e.g. companion, while the extension just appeared).
            // Drop it, then invite the target once the transport has freed up.
            session.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.isRunning, let browser = self.browser else { return }
                if !self.session.connectedPeers.contains(target), self.knownPeers.contains(target) {
                    browser.invitePeer(target, to: self.session, withContext: nil, timeout: 10)
                }
            }
        }
    }

    private func checkLiveness() {
        guard isRunning else { return }
        let idleFor = Date().timeIntervalSince(lastReceivedAt)
        if !session.connectedPeers.isEmpty {
            // Connected on paper but silent too long → zombie session. Drop it and rebuild.
            if idleFor > Self.livenessTimeout {
                session.disconnect()
                connectionState = .searching
                restartDiscovery()
            }
        } else if idleFor > Self.searchGrace {
            // Not connected and discovery has been fruitless for a while → browser may be
            // wedged. The grace window leaves the initial handshake undisturbed.
            restartDiscovery()
        }
    }
}

extension MultipeerConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if let peer = session.connectedPeers.first {
                self.connectionState = .connected(peerName: peer.displayName)
                self.lastReceivedAt = Date() // fresh grace period on (re)connect
            } else if self.isRunning {
                // Stay searching. Discovery keeps running; the watchdog rebuilds it only if
                // this drags on — never here, mid-handshake, where it would abort the connect.
                self.connectionState = .searching
            } else {
                self.connectionState = .idle
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lastReceivedAt = Date()
        guard let tagByte = data.first, let tag = PacketTag(rawValue: tagByte) else { return }
        let payload = data.dropFirst()

        switch tag {
        case .controlMessage:
            guard let message = try? JSONDecoder().decode(DashboardMessage.self, from: payload) else { return }
            switch message {
            case .batteryStatus(let level, let isCharging):
                DispatchQueue.main.async {
                    self.batteryStatus = BatteryStatus(level: level, isCharging: isCharging)
                }
            case .location(let latitude, let longitude):
                DispatchQueue.main.async {
                    self.deviceLocation = DeviceLocation(latitude: latitude, longitude: longitude)
                }
            case .videoConfig(let sps, let pps):
                videoConfigReceived = true
                onVideoConfig?(sps, pps)
            case .heartbeat:
                heartbeatsReceived += 1 // its main job is to bump lastReceivedAt, done above
            }
        case .videoFrame:
            videoPacketsReceived += 1
            onVideoFrame?(Data(payload))
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("MultipeerConnectionManager advertising error: \(error)")
    }
}

extension MultipeerConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            self.knownPeers.insert(peerID)
            self.connectToBest()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.knownPeers.remove(peerID)
            self.connectToBest() // e.g. broadcast stopped → fall back to the companion
            if self.session.connectedPeers.isEmpty, self.isRunning {
                self.connectionState = .searching
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("MultipeerConnectionManager browsing error: \(error)")
    }
}
