import Foundation

/// An `MCPeerID` display name doubles as player identity on the wire, so it has to be
/// unique. `UIDevice.current.name` returns the bare model name ("iPhone") on modern iOS, so
/// two devices would otherwise produce identical peer IDs and the roster would collapse
/// into one entry. A short random suffix fixes that; `presentable(_:)` strips it again for
/// display so the UI never shows the plumbing.
enum PeerName {
    /// `MCPeerID` rejects display names longer than 63 UTF-8 bytes.
    static let maxUTF8Bytes = 63

    private static let separator: Character = "#"
    private static let suffixLength = 4

    static func makeUnique(base: String) -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(suffixLength)
        let tail = "\(separator)\(suffix.lowercased())"
        var trimmed = base.isEmpty ? "Player" : base
        // Trim by UTF-8 byte count, not character count — the cap MCPeerID enforces is bytes.
        while trimmed.utf8.count > maxUTF8Bytes - tail.utf8.count {
            trimmed.removeLast()
        }
        return trimmed + tail
    }

    static func presentable(_ raw: String) -> String {
        guard let cut = raw.lastIndex(of: separator) else { return raw }
        return String(raw[raw.startIndex..<cut])
    }
}
