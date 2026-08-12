import Foundation
import RealityKit

/// Carry pinch-toggle; re-grab→rotate via +Rotate (docs/GESTURES.md §1 / ARCHITECTURE.md §4).
extension ARSessionCoordinator {
    /// allowsCarry route; nil-frame still fed (§5 seam 5). Leave-carry cleanup is demoMode.didSet.
    func handleCarryRouting(frame: LandmarkFrame?, packet: FramePacket, pinchEvents: [PinchGestureEvent]) {
        guard demoMode.allowsCarry else { return }

        for pinchEvent in pinchEvents {
            switch pinchEvent {
            case .began:
                // Pest wins the hit-test over O1 — checked before selectModel's ancestor-walk
                // would otherwise resolve the same tap to the parent cube (pest content).
                if let point = pinchViewportPoint, let pest = scene.selectPest(at: point) {
                    draggedPest = pest
                    scene.setHighlighted(true, for: pest)
                    if let hit = previewWorldHit {
                        pestMoveController.begin(hit: hit, modelWorld: pest.position(relativeTo: nil))
                    }
                    break
                }

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
                    allowRotate: demoMode.allowsRotate
                ) {
                case .rotate:
                    beginRotate()

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
                if draggedPest != nil {
                    break // followed in the per-frame block below, same shape as carriedEntity
                }
                if manipulation.isActive {
                    updateRotate(ratio: ratio)
                } else {
                    let observation = CarryObservation(
                        timestamp: machineTime,
                        pinchEvent: pinchEvent,
                        target: nil
                    )
                    applyCarryEvents(carryMachine.process(observation))
                }

            case .ended, .cancelled:
                if let pest = draggedPest {
                    finishPestDrag(pest)
                    break
                }
                if manipulation.isActive {
                    endRotate(pinchEvent: pinchEvent)
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

        if let pest = draggedPest {
            if pestMoveController.isActive {
                let newTarget = pestMoveController.update(hit: previewWorldHit)
                scene.movePest(pest, toWorld: newTarget)
            } else if let hit = previewWorldHit {
                // Grab-time raycast missed its frame — start now that a hit is available,
                // same retry shape as O1's carriedEntity block below (docs/GESTURES.md §2.8).
                pestMoveController.begin(hit: hit, modelWorld: pest.position(relativeTo: nil))
            }
        }

        if carriedEntity != nil {
            if moveController.isActive {
                let newTarget = moveController.update(hit: previewWorldHit)
                scene.moveModel(toWorld: newTarget)
            } else if let hit = previewWorldHit, let model = scene.activeModel {
                // pickedUp's raycast missed its frame — start now that a hit is available.
                moveController.begin(hit: hit, modelWorld: model.position(relativeTo: nil))
            }
        }
    }

    /// Drop stranded carry on leaving Carry/Sim; does not mark previously-placed.
    /// Not `private` — `demoMode.didSet` calls this on the allow-carry → not edge.
    func endCarryIfActive() {
        if manipulation.isActive {
            finishManipulation()
        }
        if let pest = draggedPest {
            finishPestDrag(pest)
        }
        guard carriedEntity != nil || carryMachine.carried != nil else { return }
        carryMachine.reset()
        carriedEntity = nil
        moveController.reset()
        scene.setHighlighted(false)
    }

    /// Release a dragged pest: far enough from O1 → fade & delete; else leave exactly where
    /// dropped (docs/GESTURES.md pest content, `GestureTuning.pestDiscardDistance`).
    private func finishPestDrag(_ pest: ModelEntity) {
        draggedPest = nil
        defer { pestMoveController.reset() }
        scene.setHighlighted(false, for: pest)
        guard let anchor = pest.parent?.position(relativeTo: nil) else { return }
        let released = pest.position(relativeTo: nil)
        if shouldDiscardPest(releaseWorldPosition: released, anchorWorldPosition: anchor, discardDistance: tuning.pestDiscardDistance) {
            scene.removePest(pest)
        }
        // else: leave it exactly where released — no snap-back, no destroy.
    }

    private func applyCarryEvents(_ events: [CarryEvent]) {
        carriedEntity = carryMachine.carried
        for event in events {
            switch event {
            case .pickedUp:
                guard let model = scene.activeModel else { continue }
                scene.setHighlighted(true)
                // Raycast may miss this frame; don't drop the pickup — retry per-frame below (§5 loop).
                if let hit = previewWorldHit {
                    moveController.begin(hit: hit, modelWorld: model.position(relativeTo: nil))
                }

            case .putDown(let id):
                previouslyPlacedEntities.insert(id)
                moveController.reset()
                scene.setHighlighted(false)
            }
        }
    }
}
