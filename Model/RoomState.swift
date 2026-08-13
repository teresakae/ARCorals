import Foundation

/// Where the local peer is in the room lifecycle.
enum RoomPhase {
    case home
    case lobby
    case inSession
}

/// One roster entry. `id` is the raw peer display name — the transport's own identity for
/// that device — so the roster needs no second identifier to key against.
struct RoomPlayer: Identifiable, Hashable, Codable {
    let id: String
    let isHost: Bool

    var name: String { PeerName.presentable(id) }
}

enum RoomRules {
    static let maxPlayers = 4

    /// How long a guest waits on one host candidate. A declined invitation produces no
    /// callback at all, so silence is the only signal that the candidate is not coming.
    static let inviteTimeout: TimeInterval = 8

    /// How long the whole join attempt runs before giving up and returning Home.
    static let joinTimeout: TimeInterval = 25
}

/// Surfaced in the UI so a blocked Local Network permission is visibly different from a
/// mistyped room code. A denied grant on a real device fails silently and permanently — no
/// error is ever delivered — and the Simulator inherits the Mac's grant and never prompts,
/// so these counters are the only signal available.
struct DiscoveryState {
    var isAdvertising = false
    var isBrowsing = false
    var peersSeen = 0
    var peersMatchingCode = 0
}
