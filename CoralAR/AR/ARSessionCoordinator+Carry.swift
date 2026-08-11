import Foundation
import RealityKit

/// Carry (pinch-toggle pick up/place) + rotate re-grab routing dispatch.
/// Carry itself is implemented here (Gesture Build Prompt C). The rotate
/// re-grab routing rule (Prompt D) still lands in this file, on top of this.
extension ARSessionCoordinator {
    /// Called from `handleVision`, right after existing pinch processing. `frame` is nil on the
    /// dropped/nil-Vision-frame path — must still be fed so an in-flight carry can time out.
    ///
    /// `pinchEvents` is this frame's output from the shared `PinchStateMachine` (Carry does not
    /// re-derive pinch detection — ADR-019 doc reference, GESTURE_BUILD_PROMPTS.md Prompt C).
    /// Note this runs alongside, not instead of, the existing demoMode-driven Adjust/Move grab
    /// flow in `handleGestureEvent` — both currently react to the same event stream on the same
    /// `moveController`. Untangling that is Prompt F's job (gating table), not this one's.
    func handleCarryRouting(frame: LandmarkFrame?, packet: FramePacket, pinchEvents: [PinchGestureEvent]) {
        for pinchEvent in pinchEvents {
            let target: EntityID?
            if case .began = pinchEvent, let point = pinchViewportPoint,
               let model = scene.selectModel(at: point) {
                target = EntityID(model)
            } else {
                target = nil
            }

            let observation = CarryObservation(timestamp: machineTime, pinchEvent: pinchEvent, target: target)
            let events = carryMachine.process(observation)
            carriedEntity = carryMachine.carried

            for event in events {
                switch event {
                case .pickedUp:
                    guard let model = scene.activeModel, let hit = previewWorldHit else { continue }
                    moveController.begin(hit: hit, modelWorld: model.position(relativeTo: nil))
                    scene.setHighlighted(true)

                case .putDown:
                    moveController.reset()
                    scene.setHighlighted(false)
                }
            }
        }

        if carriedEntity != nil, moveController.isActive {
            let newTarget = moveController.update(hit: previewWorldHit)
            scene.moveModel(toWorld: newTarget)
        }

        scene.updateContactShadow()
    }
}
