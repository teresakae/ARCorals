import SwiftUI
import UIKit

/// One screen per room phase. Home → Lobby → Session, with no navigation between them: the
/// phase is owned by `RoomSession` and, for a guest, changed by the host.
///
/// Owns the `RoomSession`, so `CoralARApp`'s AR shortcut never constructs one.
struct RoomFlowView: View {
    @StateObject private var room = RoomSession(deviceName: UIDevice.current.name)

    /// Each phase view claims its own orientation rather than inheriting one from here. A lock on
    /// this `switch` would sit on a view whose identity does not change when the phase does, so it
    /// would fire once at launch and never again — leaving the lobby in AR's landscape after a
    /// session ends. The phase views are distinct types, so theirs fire on every transition.
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
