import Foundation
import RealityKit

/// Re-grab rotate primitives via ManipulationTracker, `yawOnly` (no scale-vs-yaw race, ever —
/// docs/GESTURES.md §1). Driven from `.rotate` mode's own routing below. `yawOnly` defaults
/// false and is unused by any other live caller now that Carry's re-grab-rotate is gone.
extension ARSessionCoordinator {
    func beginRotate(yawOnly: Bool = false) {
        guard let model = scene.activeModel else { return }
        beginManipulation(entityScale: model.scale.x, entityYaw: scene.modelYaw, yawOnly: yawOnly)
    }

    func updateRotate(ratio: Double) {
        let horizontalSlide: Double? = pinchViewportPoint.map { point in
            Double(point.x / max(cachedViewportSize.width, 1)) * tuning.horizontalSlideGain
        }
        let result = manipulation.update(ratio: ratio, yaw: horizontalSlide, now: machineTime)
        applyManipulation(result)
    }

    func endRotate(pinchEvent: PinchGestureEvent) {
        if case .ended = pinchEvent, manipulation.mode == .scale {
            scene.regenerateCollisionShapes()
        }
        finishManipulation()
    }

    /// `.rotate` mode routing: ANY pinch on a placed object rotates it, yaw-only, full stop —
    /// no move capability, no history-based inference (docs/GESTURES.md §1). Nothing placed /
    /// no hit → no-op, matching Carry/Sim's convention of doing nothing on an empty target
    /// (`routeCarryPinch` returns nil the same way).
    func handleRotateModeRouting(frame: LandmarkFrame?, packet: FramePacket, pinchEvents: [PinchGestureEvent]) {
        guard demoMode.allowsRotateMode else { return }

        for pinchEvent in pinchEvents {
            switch pinchEvent {
            case .began:
                guard !manipulation.isActive else { break }
                guard let point = pinchViewportPoint, scene.selectModel(at: point) != nil else {
                    break // no placed object under the pinch → no-op
                }
                metrics.beginGesture()
                beginRotate(yawOnly: true)

            case .changed(let ratio):
                guard manipulation.isActive else { break }
                updateRotate(ratio: ratio)

            case .ended, .cancelled:
                guard manipulation.isActive else { break }
                endRotate(pinchEvent: pinchEvent)

            case .possible, .failed:
                break
            }
        }
    }

    /// Drop a stranded rotate on leaving `.rotate` mid-gesture. Not `private` —
    /// `demoMode.didSet` calls this on the allow-rotateMode → not edge, mirrors `endCarryIfActive()`.
    func endRotateModeIfActive() {
        guard manipulation.isActive else { return }
        finishManipulation()
    }
}
