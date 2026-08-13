import SwiftUI

struct InSessionView: View {
    @ObservedObject var room: RoomSession
    /// Presented rather than pushed: AR wants the whole screen, and dismissing has to return
    /// to the roster without leaving the room.
    ///
    /// Starts `true` so starting a session drops straight into AR. This view is built by
    /// `RoomFlowView` only while the phase is `.inSession`, so "the initial value" and "the
    /// session just started" are the same moment — for the host who pressed Start and for every
    /// guest the host brings along, since both arrive here by the same phase change. The roster
    /// underneath is still reachable by dismissing, and "Enter AR" gets you back in.
    @State private var isShowingAR = true

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
            .orientationLock(.landscapeRight)
        }
        // Restoring portrait on the way out has to be driven by the flag, not by an `onDisappear`
        // on the cover: dismissal is also triggered below when the session ends, and the room
        // screens underneath never re-appear (they were never removed), so their own
        // `.orientationLock` would not fire again.
        .onChange(of: isShowingAR) { _, showing in
            if !showing { OrientationLock.lock(to: .portrait) }
        }
        // The host can end the session, and a guest can be dropped, while AR is on screen.
        .onChange(of: room.phase) { _, phase in
            if phase != .inSession { isShowingAR = false }
        }
    }
}
