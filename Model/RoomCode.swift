import Foundation

/// Four-digit numeric room code. Stored as text, not an integer: leading zeros are
/// meaningful ("0042" and "42" are different rooms to a person typing them in), and the code
/// travels as a string in the advertiser's `discoveryInfo` either way.
struct RoomCode: Hashable, Codable, CustomStringConvertible {
    static let digitCount = 4

    let value: String

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // `isNumber` alone accepts non-ASCII digit characters, which would not survive the
        // round trip through discoveryInfo intact.
        guard trimmed.count == Self.digitCount, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.value = trimmed
    }

    static func random() -> RoomCode {
        RoomCode(String(format: "%0\(digitCount)d", Int.random(in: 0..<10_000)))!
    }

    var description: String { value }
}
