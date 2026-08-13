import SwiftUI
import UIKit

/// One screen per room phase. Home → Lobby → Session, with no navigation between them: the
/// phase is owned by `RoomSession` and, for a guest, changed by the host.
///
/// Owns the `RoomSession`, so `CoralARApp`'s AR shortcut never constructs one.
struct RoomFlowView: View {
    @StateObject private var room = RoomSession(deviceName: UIDevice.current.name)

    var body: some View {
        switch room.phase {
        case .home:
            HomeView(room: room)
        case .lobby:
            LobbyView(room: room)
        case .inSession:
            InSessionView(room: room)
        }
    }
}
