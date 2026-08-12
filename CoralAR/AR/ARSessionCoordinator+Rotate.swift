import Foundation
import RealityKit

/// Re-grab rotate via ManipulationTracker; allowsRotate (.carry only) (docs/GESTURES.md §2.3).
extension ARSessionCoordinator {
    func beginRotate() {
        guard let model = scene.activeModel else { return }
        beginManipulation(entityScale: model.scale.x, entityYaw: scene.modelYaw)
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
}
