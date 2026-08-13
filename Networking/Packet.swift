import Foundation
import MultipeerConnectivity

/// What a frame carries, and — for opaque payloads — the delivery guarantee its author
/// asked for.
///
/// Reliability lives in this tag byte rather than in a side channel because the host relays
/// guest traffic on their behalf (see `PeerTransport`). A relaying host has to forward with
/// the *author's* guarantee, and reading it back out of the frame is the only way to do that
/// without tracking per-sender state it has no business owning.
enum PacketTag: UInt8 {
    /// A `RoomMessage`, JSON-encoded. Room control is always reliable and never relayed —
    /// the host is the sole author of roster and phase.
    case control = 0
    case payloadReliable = 1
    case payloadUnreliable = 2

    var sendMode: MCSessionSendDataMode {
        self == .payloadUnreliable ? .unreliable : .reliable
    }
}

/// Delivery guarantee requested by whoever hands a payload to the room layer.
enum Reliability {
    case reliable
    case unreliable

    var tag: PacketTag {
        switch self {
        case .reliable: .payloadReliable
        case .unreliable: .payloadUnreliable
        }
    }
}

/// One framed message.
///
/// Layout: `[tag: 1][originLength: 1][origin: n UTF-8 bytes][body: rest]`
///
/// `origin` is in the frame because `MCSession` reports the peer it received from, which for
/// a relayed packet is the host rather than the author. One length byte is enough — peer
/// names are capped at 63 UTF-8 bytes by `PeerName`.
struct Packet {
    let tag: PacketTag
    /// Raw peer display name (suffix included) of the *original* sender.
    let origin: String
    let body: Data

    init(tag: PacketTag, origin: String, body: Data) {
        self.tag = tag
        self.origin = origin
        self.body = body
    }

    func encoded() -> Data {
        let originBytes = Array(origin.utf8.prefix(PeerName.maxUTF8Bytes))
        var frame = Data([tag.rawValue, UInt8(originBytes.count)])
        frame.append(contentsOf: originBytes)
        frame.append(body)
        return frame
    }

    init?(decoding frame: Data) {
        guard frame.count >= 2, let tag = PacketTag(rawValue: frame[frame.startIndex]) else { return nil }
        let originLength = Int(frame[frame.startIndex + 1])
        guard frame.count >= 2 + originLength else { return nil }

        let originStart = frame.startIndex + 2
        let bodyStart = originStart + originLength
        // Re-wrap both slices as fresh `Data`. A slice inherits the parent's non-zero
        // startIndex, and that breaks JSONDecoder and NSKeyedUnarchiver in ways that read
        // as payload corruption rather than as an indexing mistake.
        guard let origin = String(data: Data(frame[originStart..<bodyStart]), encoding: .utf8) else { return nil }

        self.tag = tag
        self.origin = origin
        self.body = Data(frame[bodyStart...])
    }
}
