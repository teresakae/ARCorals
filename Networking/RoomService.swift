import Foundation

/// Bonjour vocabulary shared by the advertiser and the browser.
enum RoomService {
    /// Bonjour service type. Max 15 characters, lowercase letters / digits / hyphens, no
    /// leading or trailing hyphen and no adjacent hyphens. Violations throw at runtime, not
    /// at compile time. Must stay in sync with `NSBonjourServices` in Info.plist, which
    /// lists both `_coral-rooms._tcp` and `_coral-rooms._udp` — MultipeerConnectivity uses
    /// both, and omitting either makes discovery silently find nothing.
    static let type = "coral-rooms"

    /// Keys in the advertiser's `discoveryInfo`. The room code travels here so a browsing
    /// guest can filter candidates without connecting, and occupancy travels here so a full
    /// room is distinguishable from a wrong code before any invite is sent.
    enum InfoKey {
        static let roomCode = "code"
        static let playerCount = "players"
        static let capacity = "capacity"
    }
}
