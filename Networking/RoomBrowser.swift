import Foundation
import MultipeerConnectivity

/// Finds advertising peers over Bonjour and invites one of them. Only a joining guest browses.
@MainActor
final class RoomBrowser: NSObject {
    private let transport: PeerTransport
    private var browser: MCNearbyServiceBrowser?
    /// The exact `MCPeerID` instances handed over by discovery — `invitePeer` needs those,
    /// not a same-named replacement.
    private var foundPeers: [String: MCPeerID] = [:]

    private(set) var isBrowsing = false
    private(set) var lastError: String?
    /// Raw peer name → that advertiser's `discoveryInfo`. Filtering by room code is a room
    /// rule, so it happens in `RoomSession` and not here.
    private(set) var discovered: [String: [String: String]] = [:]

    var onChange: (() -> Void)?

    init(transport: PeerTransport) {
        self.transport = transport
        super.init()
    }

    func start() {
        stop()
        let browser = MCNearbyServiceBrowser(peer: transport.localPeerID, serviceType: RoomService.type)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        isBrowsing = true
        lastError = nil
        roomLog.info("browsing for \(RoomService.type, privacy: .public)")
        onChange?()
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        foundPeers.removeAll()
        discovered.removeAll()
        guard isBrowsing else { return }
        isBrowsing = false
        onChange?()
    }

    func invite(_ peerName: String, timeout: TimeInterval) {
        guard let browser, let peer = foundPeers[peerName] else { return }
        // No context data: the peer's display name already carries the player's identity, so
        // the host builds the roster entry from the connection alone.
        browser.invitePeer(peer, to: transport.session, withContext: nil, timeout: timeout)
        roomLog.info("invited \(peerName, privacy: .public)")
    }
}

extension RoomBrowser: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let token = PeerToken(peerID: peerID)
        let info = info ?? [:]
        Task { @MainActor in
            self.foundPeers[token.peerID.displayName] = token.peerID
            self.discovered[token.peerID.displayName] = info
            roomLog.info("found \(token.peerID.displayName, privacy: .public) \(info, privacy: .public)")
            self.onChange?()
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in
            self.foundPeers[name] = nil
            self.discovered[name] = nil
            roomLog.info("lost \(name, privacy: .public)")
            self.onChange?()
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.isBrowsing = false
            self.lastError = message
            roomLog.error("browsing failed: \(message, privacy: .public)")
            self.onChange?()
        }
    }
}

/// `MCPeerID` carries no `Sendable` annotation, but it is an immutable identity object fixed
/// at construction. Boxing it is what lets a delegate callback on an arbitrary queue hand the
/// token to the main actor, which is the only place it is ever stored or read.
private struct PeerToken: @unchecked Sendable {
    let peerID: MCPeerID
}
