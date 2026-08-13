import SwiftUI

/// Shown on Home and in the Lobby so a blocked Local Network permission looks different
/// from a mistyped code. Denial on a real device is delivered as silence, so these four
/// values are the only evidence available — see `DiscoveryState`.
struct DiscoveryStatusSection: View {
    let discovery: DiscoveryState

    var body: some View {
        Section("Discovery") {
            LabeledContent("Advertising", value: discovery.isAdvertising ? "Yes" : "No")
            LabeledContent("Browsing", value: discovery.isBrowsing ? "Yes" : "No")
            LabeledContent("Rooms seen", value: String(discovery.peersSeen))
            LabeledContent("Matching code", value: String(discovery.peersMatchingCode))
        }
    }
}
