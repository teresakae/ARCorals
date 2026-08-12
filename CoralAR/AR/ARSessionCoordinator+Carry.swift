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

        if carriedEntity != nil, moveController.isActive {
            let newTarget = moveController.update(hit: previewWorldHit)
            scene.moveModel(toWorld: newTarget)
        }
    }

    /// Drop stranded carry on leaving Carry/Sim; does not mark previously-placed.
    /// Not `private` — `demoMode.didSet` calls this on the allow-carry → not edge.
    func endCarryIfActive() {
        if manipulation.isActive {
            finishManipulation()
        }
        guard carriedEntity != nil || carryMachine.carried != nil else { return }
        carryMachine.reset()
        carriedEntity = nil
        moveController.reset()
        scene.setHighlighted(false)
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
