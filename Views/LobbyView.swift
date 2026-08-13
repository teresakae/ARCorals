import SwiftUI

struct LobbyView: View {
    @ObservedObject var room: RoomSession

    var body: some View {
        NavigationStack {
            List {
                Section("Room") {
                    LabeledContent("Code", value: room.roomCode?.value ?? "—")
                    LabeledContent("Role", value: room.isHost ? "Host" : "Guest")
                }

                RosterSection(players: room.players, localPlayerID: room.localPlayerID)

                Section {
                    if room.isHost {
                        Button("Start Session") { room.startSession() }
                    }
                    Button("Leave Room", role: .destructive) { room.leaveRoom() }
                }
            }
            .navigationTitle("Lobby")
        }
        // Also the landing point when a session ends, which is the transition that arrives
        // straight out of AR's landscape.
        .orientationLock(.portrait)
    }
}
