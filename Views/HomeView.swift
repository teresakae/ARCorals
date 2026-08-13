import SwiftUI

struct HomeView: View {
    @ObservedObject var room: RoomSession
    @State private var codeEntry = ""

    private var enteredCode: RoomCode? { RoomCode(codeEntry) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    Button("Create Room") { room.createRoom() }
                }

                Section("Join") {
                    TextField("Room code", text: $codeEntry)
                        .keyboardType(.numberPad)
                    Button("Join Room") {
                        guard let enteredCode else { return }
                        room.joinRoom(code: enteredCode)
                    }
                    .disabled(enteredCode == nil)
                }

                if room.isJoining {
                    Section("Joining") {
                        ProgressView()
                        Button("Cancel", role: .cancel) { room.cancelJoin() }
                    }
                }

                DiscoveryStatusSection(discovery: room.discovery)

                if let status = room.status {
                    Section("Status") { Text(status) }
                }
            }
            .navigationTitle("Coral Rooms")
        }
    }
}
