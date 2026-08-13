import SwiftUI

struct InSessionView: View {
    @ObservedObject var room: RoomSession
    /// Presented rather than pushed: AR wants the whole screen, and dismissing has to return
    /// to the roster without leaving the room.
    @State private var isShowingAR = false

    var body: some View {
        NavigationStack {
            List {
                Section("Room") {
                    LabeledContent("Code", value: room.roomCode?.value ?? "—")
                    LabeledContent("Role", value: room.isHost ? "Host" : "Guest")
                }

                RosterSection(players: room.players, localPlayerID: room.localPlayerID)

                Section("Content") {
                    Button("Enter AR") { isShowingAR = true }
                }

                if let status = room.status {
                    Section("Status") { Text(status) }
                }

                Section {
                    if room.isHost {
                        Button("End Session") { room.endSession() }
                    }
                    Button("Leave Room", role: .destructive) { room.leaveRoom() }
                }
            }
            .navigationTitle("Session")
        }
        .fullScreenCover(isPresented: $isShowingAR) {
            ZStack(alignment: .topLeading) {
                ARRootView()
                Button("Back to Room") { isShowingAR = false }
                    .padding()
            }
        }
        // The host can end the session, and a guest can be dropped, while AR is on screen.
        .onChange(of: room.phase) { _, phase in
            if phase != .inSession { isShowingAR = false }
        }
    }
}
