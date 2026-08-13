import SwiftUI

struct RosterSection: View {
    let players: [RoomPlayer]
    let localPlayerID: String

    var body: some View {
        Section("Players \(players.count) of \(RoomRules.maxPlayers)") {
            if players.isEmpty {
                Text("Waiting for the roster.")
                    .foregroundStyle(.secondary)
            }
            ForEach(players) { player in
                LabeledContent(player.name, value: tags(for: player))
            }
        }
    }

    private func tags(for player: RoomPlayer) -> String {
        var tags: [String] = []
        if player.isHost { tags.append("Host") }
        if player.id == localPlayerID { tags.append("You") }
        return tags.joined(separator: " · ")
    }
}
