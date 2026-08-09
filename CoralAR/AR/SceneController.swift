import RealityKit
import simd

/// Owns placed entities. Scale/yaw go on the child ModelEntity, never the anchor.
@MainActor
final class SceneController {
    private let arView: ARView
    private(set) var placedAnchors: [AnchorEntity] = []
    private(set) var activeModel: ModelEntity?
    /// Yaw applied to `activeModel` about world Y. Pure-Y writes only — no `move(to:)`.
    private(set) var modelYaw: Float = 0
    /// `activeModel`'s materials before `setHighlighted(true)` swapped them out.
    /// nil whenever not currently highlighted.
    private var unhighlightedMaterials: [Material]?

    var hasPlacedEntity: Bool { activeModel != nil }

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
        activeModel = model
        modelYaw = 0
        unhighlightedMaterials = nil
    }

    /// Visual feedback for "actively being grabbed" — HUD text alone is easy
    /// to miss while watching your hand. Plain material-color swap, not
    /// `HoverEffectComponent`: that component only lights up on RealityKit's
    /// own hover/gaze input pipeline, which our Vision-driven pinch gestures
    /// never feed, so it would never actually trigger here.
    func setHighlighted(_ on: Bool) {
        guard let model = activeModel else { return }
        if on {
            guard unhighlightedMaterials == nil else { return }
            unhighlightedMaterials = model.model?.materials
            var highlight = SimpleMaterial()
            highlight.color = .init(tint: .systemYellow, texture: nil)
            model.model?.materials = [highlight]
        } else {
            guard let saved = unhighlightedMaterials else { return }
            model.model?.materials = saved
            unhighlightedMaterials = nil
        }
    }

    func applyScale(_ uniform: Float) {
        guard let model = activeModel else { return }
        model.scale = SIMD3<Float>(repeating: uniform)
    }

    func applyYaw(_ radians: Float) {
        guard let model = activeModel else { return }
        modelYaw = radians
        // Direct write — never move(to:duration:); slerp snaps past ±π (AGENTS.md).
        model.transform.rotation = simd_quatf(angle: radians, axis: [0, 1, 0])
    }

    /// Collision shapes do not track post-hoc scale (forum 733648). Call on scale Ended only.
    func regenerateCollisionShapes() {
        activeModel?.generateCollisionShapes(recursive: true)
    }

    func clearAll() {
        for anchor in placedAnchors {
            arView.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
        activeModel = nil
        modelYaw = 0
        unhighlightedMaterials = nil
    }
}
