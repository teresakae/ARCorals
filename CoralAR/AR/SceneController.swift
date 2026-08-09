import RealityKit
import simd

/// Owns placed entities. Scale/yaw go on the child ModelEntity, never the anchor.
@MainActor
final class SceneController {
    private let arView: ARView
    private(set) var placedAnchors: [AnchorEntity] = []

    init(arView: ARView) {
        self.arView = arView
    }

    func place(at worldTransform: simd_float4x4) {
        let anchor = AnchorEntity(world: worldTransform)
        let model = ModelProvider.makePlaceholder()
        // Lift half the cube height so it sits on the plane, not through it.
        model.position = [0, 0.025, 0]
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
        placedAnchors.append(anchor)
    }

    func clearAll() {
        for anchor in placedAnchors {
            arView.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
    }
}
