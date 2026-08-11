import Foundation
import RealityKit

/// Carry (pinch-toggle pick up/place) + rotate re-grab routing dispatch.
/// Carry itself is Prompt C; re-grab → ManipulationTracker yaw is Prompt D.
extension ARSessionCoordinator {
    /// Called from `handleVision`, right after existing pinch processing. `frame` is nil on the
    /// dropped/nil-Vision-frame path — must still be fed so an in-flight carry can time out.
    ///
    /// Only runs when `demoMode.allowsCarry` (`.carry` / `.sim`). Adjust/Move keep the legacy
    /// `handleGestureEvent` path untouched; running both on the same pinch raced Carry's
    /// pickup against `finishManipulation()` (Prompt D finding from Prompt C).
    ///
    /// `pinchEvents` is this frame's output from the shared `PinchStateMachine` — Carry does
    /// not re-derive pinch detection.
    func handleCarryRouting(frame: LandmarkFrame?, packet: FramePacket, pinchEvents: [PinchGestureEvent]) {
        guard demoMode.allowsCarry else { return }

        for pinchEvent in pinchEvents {
            switch pinchEvent {
            case .began:
                let target: EntityID?
                if let point = pinchViewportPoint, let model = scene.selectModel(at: point) {
                    target = EntityID(model)
                } else {
                    target = nil
                }

                switch routeCarryPinch(
                    target: target,
                    previouslyPlaced: previouslyPlacedEntities,
                    isCarrying: carriedEntity != nil,
                    allowRotate: demoMode == .carry
                ) {
                case .rotate:
                    guard let model = scene.activeModel else { break }
                    manipulation.begin(entityScale: model.scale.x, entityYaw: scene.modelYaw)
                    scene.setHighlighted(true)

                case .carry:
                    let observation = CarryObservation(
                        timestamp: machineTime,
                        pinchEvent: pinchEvent,
                        target: target
                    )
                    applyCarryEvents(carryMachine.process(observation))

                case nil:
                    break
                }

            case .changed(let ratio):
                if manipulation.isActive {
                    let horizontalSlide: Double? = pinchViewportPoint.map { point in
                        Double(point.x / max(cachedViewportSize.width, 1)) * tuning.horizontalSlideGain
                    }
                    let result = manipulation.update(ratio: ratio, yaw: horizontalSlide, now: machineTime)
                    applyManipulation(result)
                    if result.didLock {
                        stateMachine.exitThresholdOverride = tuning.scaleModeExitThreshold
                    }
                } else {
                    let observation = CarryObservation(
                        timestamp: machineTime,
                        pinchEvent: pinchEvent,
                        target: nil
                    )
                    applyCarryEvents(carryMachine.process(observation))
                }

            case .ended, .cancelled:
                if manipulation.isActive {
                    if case .ended = pinchEvent, manipulation.mode == .scale {
                        scene.regenerateCollisionShapes()
                    }
                    finishManipulation()
                } else {
                    let observation = CarryObservation(
                        timestamp: machineTime,
                        pinchEvent: pinchEvent,
                        target: nil
                    )
                    applyCarryEvents(carryMachine.process(observation))
                }

            case .possible, .failed:
                break
            }
        }

        if carriedEntity != nil, moveController.isActive {
            let newTarget = moveController.update(hit: previewWorldHit)
            scene.moveModel(toWorld: newTarget)
        }
    }

    private func applyCarryEvents(_ events: [CarryEvent]) {
        carriedEntity = carryMachine.carried
        for event in events {
            switch event {
            case .pickedUp:
                guard let model = scene.activeModel, let hit = previewWorldHit else { continue }
                moveController.begin(hit: hit, modelWorld: model.position(relativeTo: nil))
                scene.setHighlighted(true)

            case .putDown(let id):
                previouslyPlacedEntities.insert(id)
                moveController.reset()
                scene.setHighlighted(false)
            }
        }
    }
}
