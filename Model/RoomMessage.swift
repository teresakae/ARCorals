import Foundation

/// Room control traffic, JSON-encoded into a `.control` packet.
///
/// Every case travels host → guest. The host is the sole authority on the roster and the
/// phase, so guests never author one of these and the host never relays one. Leaving a room
/// is a plain disconnect rather than a message, which means it also covers a crash or a peer
/// walking out of range.
enum RoomMessage: Codable {
    /// The complete roster, host first. Guests replace their copy wholesale rather than
    /// merging, so the two devices cannot drift.
    case roster([RoomPlayer])
    case roomFull
    case startSession
    case endSession

    func encodedPacket(origin: String) throws -> Packet {
        Packet(tag: .control, origin: origin, body: try JSONEncoder().encode(self))
    }

    init(decoding packet: Packet) throws {
        self = try JSONDecoder().decode(RoomMessage.self, from: packet.body)
    }
}
