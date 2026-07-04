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

    /// Bypasses @Published on purpose: video frames can arrive up to 30x/sec and a decoder
    /// consumes them directly, so routing them through SwiftUI diffing would be wasteful.
    var onVideoFrame: ((Data) -> Void)?

    /// Delivered off the network thread whenever the sender re-announces its H.264
    /// parameter sets (SPS/PPS), i.e. on every keyframe. Routed to the decoder directly
    /// rather than through a shared @Published slot so it never contends with battery updates.
    var onVideoConfig: ((_ sps: Data, _ pps: Data) -> Void)?

    private let role: PeerRole
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session: MCSession = {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        return session
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    init(role: PeerRole) {
        self.role = role
        super.init()
    }

    func start() {
        guard case .idle = connectionState else { return }
        connectionState = .searching
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

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
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
}

extension MultipeerConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionState = .connected(peerName: peerID.displayName)
            case .connecting, .notConnected:
                self.connectionState = .searching
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
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
                onVideoConfig?(sps, pps)
            }
        case .videoFrame:
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
}

extension MultipeerConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if case .connected(let name) = self.connectionState, name == peerID.displayName {
                self.connectionState = .searching
            }
        }
    }
}
