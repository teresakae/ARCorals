import Foundation

/// The seam the AR module plugs into. Declared now, implemented later — `RoomSession` holds a
/// `nil` reference until something conforms, and adding a conformer requires no change to
/// anything under `Networking/`.
///
/// Payloads are opaque `Data` in both directions. The room layer never inspects a body, and
/// the AR module never names a recipient: outbound routing is `RoomSession`'s job, which is
/// what keeps the star topology (guests to the host, host to everyone else) from leaking out
/// of the transport and into AR code.
@MainActor
protocol ARPayloadChannel: AnyObject {
    /// Assigned by `RoomSession`. Calling it transmits; the room layer picks the recipients.
    var sendPayload: ((Data, Reliability) -> Void)? { get set }

    /// A payload authored by `origin` — the *original* sender, even when the host relayed it.
    func receivePayload(_ payload: Data, from origin: RoomPlayer.ID)

    func roomSessionDidStart(localPlayer: RoomPlayer, roster: [RoomPlayer])
    func rosterDidChange(_ roster: [RoomPlayer])
    func roomSessionDidEnd()
}
