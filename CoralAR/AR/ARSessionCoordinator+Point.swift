import CoreGraphics
import Foundation

/// Point-and-dwell → popup; allowsPoint; nil target when off ends dwell (docs/GESTURES.md §2.9).
extension ARSessionCoordinator {
    /// Fixed 2D test target — posehandtest's `ControlPanelView` button, ported as a placeholder
    /// so Point mode's hit-test/dwell logic can be exercised against a simple screen-space
    /// rect instead of only the harder-to-hit 3D annotation marker on the placed model.
    static let testButtonID = AnnotationID("Test Button")

    /// After carry/rotate; nil frame still fed so dwell times out (docs/ARCHITECTURE.md §5 seam 5).
    func handlePoint(frame: LandmarkFrame?, packet: FramePacket) {
        var target: AnnotationID?
        // `HandShapeClassifier.isPointing` is measured here for `debugIsPointing`'s HUD readout
        // only — it does NOT gate the dwell below. Its extension/pinch thresholds are the same
        // uncalibrated 1.2/1.48 anthropometric ratios `GESTURES.md` §2.9 flags as unmeasured, and
        // they contradict each other for a natural pointing hand (index-out, thumb-folded reads
        // as BOTH "not pointing" and "pinching"), which made dwell unreachable — see chat: Point
        // mode couldn't hit anything, geometry was fine, this was why. posehandtest has no shape
        // gate at all: the dwell timer itself is the intent filter (nobody holds a fingertip
        // still on a target for 0.4s by accident). Same here now.
        var isPointing = false

        if demoMode.allowsPoint, let frame {
            isPointing = HandShapeClassifier.isPointing(joints: frame.joints, confidenceGate: tuning.confidenceGate, tuning: tuning, dyAspectCorrection: packet.dyAspectCorrection)

            if let visionPoint = frame.indexTipPoint(confidenceGate: tuning.confidenceGate) {
                let rawPoint = viewportPoint(visionPoint, packet: packet)
                // Smoothed, same as posehandtest — a jittery raw point flickers in and out of a
                // small hit-test rect frame to frame, which reads as "can't hit the target" even
                // when it's visually on it. Hit-test the smoothed point, not the raw one, so the
                // crosshair and the hit-test always agree.
                let viewPoint = pointSmoother.smooth(rawPoint)
                pointViewportPoint = viewPoint
                // Layer 1 — 2D UI wins, same ordering as posehandtest's PointerInteractionResolver:
                // the button visually occludes the scene, so it should win the hit-test too.
                if testButtonFrame.contains(viewPoint) {
                    target = Self.testButtonID
                } else {
                    target = scene.selectAnnotation(at: viewPoint)
                }
            } else {
                // Index tip not confident this frame — don't leave a stale crosshair sitting
                // wherever it last was (posehandtest hides its cursor the same way on hand loss).
                pointViewportPoint = nil
                pointSmoother.reset()
            }
        } else {
            pointViewportPoint = nil
            pointSmoother.reset()
        }

        // Point mode's legacy pinch path is fully dead (GESTURES.md §1) — there's no gesture for
        // dwell to conflict with, so it must never cancel dwell here. It used to read
        // `stateMachine.phase`, which a natural pointing hand (thumb folded, index out) trips
        // into `.began` under the same uncalibrated ratio noted above, wiping `dwellProgress`
        // to 0 every single frame. Same "why can't I hit anything" bug as `isPointing` above.
        let observation = PointObservation(timestamp: machineTime, target: target, isPointing: true, pinchActive: false)
        let events = pointStateMachine.process(observation)
        dwellProgress = pointStateMachine.dwellProgress
        debugIsPointing = isPointing
        debugPointTarget = target != nil
        isPointingAtTestButton = target == Self.testButtonID

        for event in events {
            switch event {
            case .hoverBegan(let id):
                activeAnnotationID = id
            case .hoverEnded(let id):
                if activeAnnotationID == id {
                    activeAnnotationID = nil
                }
            }
        }
    }
}
