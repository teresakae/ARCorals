import Foundation
import MultipeerConnectivity

/// Owns the `MCSession`, frames every message, and — when this peer is the host — relays
/// guest traffic on their behalf.
///
/// **Star topology.** Two guests that both joined the host's session are *not* guaranteed to
/// be connected to each other, so guests transmit only to the host and the host re-sends to
/// everyone else. A naive "send to all connected peers" looks correct with two players and
/// silently drops traffic at three or four, which is an expensive bug to find later.
///
/// Knows nothing about AR. It moves opaque `Data` and does not interpret a payload body.
@MainActor
final class PeerTransport: NSObject {
    let localPeerID: MCPeerID
    let session: MCSession

    /// Set by `RoomSession` when this peer becomes the host. Guests never relay.
    var isRelayHost = false

    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?
    var onPacket: ((Packet) -> Void)?

    var localName: String { localPeerID.displayName }
    var connectedPeerNames: [String] { session.connectedPeers.map(\.displayName) }

    /// `deviceName` is made collision-proof here rather than by the caller, so nothing above
    /// this layer has to know about `MCPeerID`'s 63-byte limit — see `PeerName`.
    init(deviceName: String) {
        let localPeerID = MCPeerID(displayName: PeerName.makeUnique(base: deviceName))
        self.localPeerID = localPeerID
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func disconnect() {
        session.disconnect()
    }

    func send(_ packet: Packet, to peerName: String) {
        transmit(packet.encoded(), to: session.connectedPeers.filter { $0.displayName == peerName }, mode: packet.tag.sendMode)
    }

    func broadcast(_ packet: Packet, excluding excludedPeerName: String? = nil) {
        transmit(packet.encoded(), to: peers(excluding: excludedPeerName), mode: packet.tag.sendMode)
    }

    private func peers(excluding excludedPeerName: String?) -> [MCPeerID] {
        session.connectedPeers.filter { $0.displayName != excludedPeerName }
    }

    private func transmit(_ frame: Data, to peers: [MCPeerID], mode: MCSessionSendDataMode) {
        guard !peers.isEmpty else { return }
        do {
            try session.send(frame, toPeers: peers, with: mode)
        } catch {
            roomLog.error("send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receive(_ frame: Data, from senderName: String) {
        guard let packet = Packet(decoding: frame) else {
            roomLog.error("dropped malformed frame from \(senderName, privacy: .public)")
            return
        }
        // Relay before delivering locally: the frame already carries the author and the
        // reliability the author asked for, so forwarding it byte-for-byte needs no extra
        // bookkeeping. Control messages are never relayed — the host authors those.
        if isRelayHost, packet.tag != .control {
            transmit(frame, to: peers(excluding: senderName), mode: packet.tag.sendMode)
        }
        onPacket?(packet)
    }
}

// MultipeerConnectivity delivers these on arbitrary queues, so they are `nonisolated` and
// hop explicitly. Only `Sendable` values cross the hop — `MCPeerID` and `MCSession` carry no
// `Sendable` annotation, so the peer's display name is extracted first and the session is
// read back from `self` on the main actor.
extension PeerTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        Task { @MainActor in
            switch state {
            case .connected:
                roomLog.info("peer connected: \(name, privacy: .public)")
                self.onPeerConnected?(name)
            case .notConnected:
                roomLog.info("peer disconnected: \(name, privacy: .public)")
                self.onPeerDisconnected?(name)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in
            self.receive(data, from: name)
        }
    }

    // Streams and resources are unused: all room traffic is small framed `Data`.
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}
