import SwiftUI
import UIKit

/// The app has two orientation regimes, not one: the room screens (Home / Lobby / Session) are
/// stock Forms that belong in portrait, and AR is landscape — `LandmarkSpace.visionOrientation(for:)`
/// and the whole hand-tracking pipeline are calibrated against a landscape camera buffer.
///
/// Info.plist therefore has to declare *both* orientations, which by itself would let every screen
/// rotate freely. This narrows the mask per screen to get the fixed-per-screen behaviour back.
///
/// Two calls are needed on each change and neither is redundant:
/// `requestGeometryUpdate` rotates the window that is already on screen, while the mask read back
/// by `OrientationLockAppDelegate` is what stops it rotating away again when the user tilts the
/// device. Doing only the first rotates once and then drifts; only the second leaves the current
/// screen stuck until the next tilt.
@MainActor
enum OrientationLock {
    /// Read by `OrientationLockAppDelegate`. Portrait is the launch regime — the room flow.
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    static func lock(to newMask: UIInterfaceOrientationMask) {
        mask = newMask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask))
        // AR is presented in a `fullScreenCover`, so the controller that has to re-ask for its
        // supported orientations is not always the one that was on screen when the mask changed.
        // Asking from the root walks down to whatever is presented on top of it.
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// UIKit asks the app delegate, not SwiftUI, what a window may rotate to — there is no SwiftUI
/// equivalent as of iOS 26, so the room flow needs this adaptor to hold the answer.
final class OrientationLockAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

extension View {
    /// Pins the app to `mask` while this view is on screen. Applied at the two boundaries that
    /// change regime — the room flow (portrait) and AR (landscape) — not per screen.
    func orientationLock(_ mask: UIInterfaceOrientationMask) -> some View {
        onAppear { OrientationLock.lock(to: mask) }
    }
}
