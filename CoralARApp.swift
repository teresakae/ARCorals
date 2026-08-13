import SwiftUI

/// The one entry point. Normal flow is the room screens first — Home → Lobby → Session —
/// and AR is entered from the session screen.
///
/// Neither branch owns state: `RoomFlowView` creates the `RoomSession` and `ARRootView`
/// creates the `ARSessionCoordinator`, so no camera or world tracking starts until the
/// player actually reaches AR.
@main
struct CoralARApp: App {
    /// Holds the per-screen orientation mask. UIKit asks the delegate, so the room flow's
    /// portrait/AR-landscape split needs one even though nothing else here does. See `OrientationLock`.
    @UIApplicationDelegateAdaptor(OrientationLockAppDelegate.self) private var appDelegate

    /// Development shortcut: flip to `true` to skip the room flow and open straight into AR.
    private let startInARDirectly = false

    var body: some SwiftUI.Scene {
        WindowGroup {
            if startInARDirectly {
                // The shortcut bypasses `RoomFlowView`, so it has to claim AR's regime itself.
                ARRootView()
                    .orientationLock(.landscapeRight)
            } else {
                RoomFlowView()
            }
        }
    }
}
