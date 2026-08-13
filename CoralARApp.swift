import SwiftUI

/// The one entry point. Normal flow is the room screens first — Home → Lobby → Session —
/// and AR is entered from the session screen.
///
/// Neither branch owns state: `RoomFlowView` creates the `RoomSession` and `ARRootView`
/// creates the `ARSessionCoordinator`, so no camera or world tracking starts until the
/// player actually reaches AR.
@main
struct CoralARApp: App {
    /// Development shortcut: flip to `true` to skip the room flow and open straight into AR.
    private let startInARDirectly = false

    var body: some SwiftUI.Scene {
        WindowGroup {
            if startInARDirectly {
                ARRootView()
            } else {
                RoomFlowView()
            }
        }
    }
}
