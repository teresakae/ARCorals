import Foundation
import MultipeerConnectivity

/// Publishes this peer over Bonjour. Only the host advertises.
@MainActor
final class RoomAdvertiser: NSObject {
    private let transport: PeerTransport
    private var advertiser: MCNearbyServiceAdvertiser?

    private(set) var isAdvertising = false
    private(set) var lastError: String?

    /// Host-side capacity gate. Returning `false` declines the invite, which is how a
    /// room-full join is refused; `RoomSession` also publishes occupancy in `discoveryInfo`
    /// so the guest can see the reason without waiting for the decline.
    var shouldAcceptInvitation: (() -> Bool)?
    var onStateChange: (() -> Void)?

    init(transport: PeerTransport) {
        self.transport = transport
        super.init()
    }

    /// Restarting on every roster change is deliberate: `discoveryInfo` is fixed when the
    /// advertiser is constructed, so a changed player count only reaches browsers by
    /// replacing the advertiser.
    func start(discoveryInfo: [String: String]) {
        stop()
        let advertiser = MCNearbyServiceAdvertiser(
            peer: transport.localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: RoomService.type
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        isAdvertising = true
        lastError = nil
        roomLog.info("advertising \(discoveryInfo, privacy: .public)")
        onStateChange?()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        guard isAdvertising else { return }
        isAdvertising = false
        onStateChange?()
    }
}

extension RoomAdvertiser: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let name = peerID.displayName
        let handler = InvitationResponder(handler: invitationHandler)
        Task { @MainActor in
            let accept = self.shouldAcceptInvitation?() ?? false
            roomLog.info("invitation from \(name, privacy: .public): \(accept ? "accepted" : "declined", privacy: .public)")
            handler.respond(accept: accept, session: accept ? self.transport.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.isAdvertising = false
            self.lastError = message
            roomLog.error("advertising failed: \(message, privacy: .public)")
            self.onStateChange?()
        }
    }
}

/// The invitation callback is an Objective-C block with no `Sendable` annotation, and the
/// accept/decline decision needs main-actor state (the roster count). Boxing it is what lets
/// the decision hop to the main actor; the block is called exactly once, from that one place.
private struct InvitationResponder: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void

    func respond(accept: Bool, session: MCSession?) {
        handler(accept, session)
    }
}
