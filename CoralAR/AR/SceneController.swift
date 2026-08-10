import RealityKit
import simd
import CoreGraphics

/// Owns placed entities. Scale/yaw go on the child ModelEntity, never the anchor.
@MainActor
final class SceneController {
    private let arView: ARView
    private(set) var placedAnchors: [AnchorEntity] = []
    private(set) var placedModels: [ModelEntity] = []
    /// The entity Adjust/Move act on. Reassigned on `place()` and, per grab,
    /// by `selectModel(at:)` — real spatial selection: whichever placed
    /// entity the pinch point's viewport position actually hit-tests onto.
    /// No more "most-recently-placed-or-grabbed" guessing.
    private(set) var activeModel: ModelEntity?
    /// Yaw of `activeModel` about world Y, decoded from its own transform —
    /// per-model, not a single stored field. A stored field was wrong with
    /// multiple objects: place() reset it to 0 and grabbing object B reused
    /// whatever object A left behind as the baseline, snapping B's rotation
    /// on the first yaw frame after switching objects. Since every write here
    /// is a pure-Y `simd_quatf` (never `move(to:)` — AGENTS.md), decoding
    /// back is exact: real = cos(θ/2), y-imaginary = sin(θ/2).
    var modelYaw: Float {
        guard let model = activeModel else { return 0 }
        let q = model.transform.rotation.vector
        return 2 * atan2(q.y, q.w)
    }
    /// `activeModel`'s materials before `setHighlighted(true)` swapped them out.
    /// nil whenever not currently highlighted.
    private var unhighlightedMaterials: [Material]?

    var hasPlacedEntity: Bool { activeModel != nil }

    init(arView: ARView) {
        self.arView = arView
    }

    /// Adds a new object every call — does not clear existing ones (that's
    /// the caller's choice, see ARSessionCoordinator's Place-mode handling).
    /// The newly-placed entity becomes active per the most-recently-touched
    /// rule (see `activeModel` doc).
    func place(at worldTransform: simd_float4x4) {
        // Position only, rotation dropped: the raycast's transform carries the
        // hit plane's orientation, and on the .estimatedPlane tier that normal
        // is a guess that can come back visibly off-vertical — which tilts the
        // whole anchor and stands the cube up crooked on a flat table. An
        // identity-rotation anchor is gravity-aligned by construction. Nothing
        // downstream wanted the plane's yaw either: applyYaw writes an absolute
        // world-Y rotation on the child, and modelYaw decodes it back.
        var upright = matrix_identity_float4x4
        upright.columns.3 = worldTransform.columns.3
        let anchor = AnchorEntity(world: upright)
        let model = ModelProvider.makePlaceholder()
        // Lift half the cube height so it sits on the plane, not through it.
        model.position = [0, ModelProvider.halfHeight, 0]
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
        placedAnchors.append(anchor)
        placedModels.append(model)
        activeModel = model
        unhighlightedMaterials = nil
    }

    /// Hit-tests `viewportPoint` against placed entities and makes whichever
    /// one it landed on active. Uses `ARView.entity(at:)`, RealityKit's own
    /// hit-testing against each entity's `CollisionComponent` — every
    /// placeholder already gets one from `ModelProvider.makePlaceholder()`,
    /// and `regenerateCollisionShapes()` keeps it current after scaling, so
    /// there's no new collision setup to add here.
    ///
    /// Fallback when the point lands on nothing placed: return nil and leave
    /// `activeModel` untouched — the grab does nothing. Picked over a
    /// nearest-within-radius fallback because it needs no new distance
    /// threshold to tune (radius-based forgiveness would have to be
    /// calibrated against real pinch/landmark noise at 30-40cm range); if
    /// missed grabs turn out common in practice, that's the first thing to add.
    @discardableResult
    func selectModel(at viewportPoint: CGPoint) -> ModelEntity? {
        guard let hit = arView.entity(at: viewportPoint) else { return nil }
        var candidate: Entity? = hit
        while let entity = candidate {
            if let model = entity as? ModelEntity, placedModels.contains(model) {
                activeModel = model
                return model
            }
            candidate = entity.parent
        }
        return nil
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
        // Scaling grows the box about its centre, so it eats down through the
        // plane as it gets bigger (and floats as it shrinks). Shift y by the
        // change in half-height so the base stays where it is — incremental,
        // so it survives moves that already changed y.
        model.position.y += ModelProvider.halfHeight * (uniform - model.scale.x)
        model.scale = SIMD3<Float>(repeating: uniform)
    }

    func applyYaw(_ radians: Float) {
        guard let model = activeModel else { return }
        // Direct write — never move(to:duration:); slerp snaps past ±π (AGENTS.md).
        model.transform.rotation = simd_quatf(angle: radians, axis: [0, 1, 0])
    }

    /// Collision shapes do not track post-hoc scale (forum 733648). Call on scale Ended only.
    func regenerateCollisionShapes() {
        activeModel?.generateCollisionShapes(recursive: true)
    }

    /// World position of the active model, for Move's absolute-from-grab math.
    var modelWorldPosition: SIMD3<Float>? {
        activeModel?.position(relativeTo: nil)
    }

    /// Move mode: write the child's position directly from a world-space
    /// target, converted through whatever the current parent anchor is.
    /// The anchor itself never moves — the child can sit at any offset from
    /// it indefinitely, this conversion works regardless (no re-anchoring).
    func moveModel(toWorld world: SIMD3<Float>) {
        guard let model = activeModel, let parent = model.parent else { return }
        model.position = parent.convert(position: world, from: nil)
    }

    // ponytail: no end-of-move re-anchor. A prior version swapped the model onto a
    // fresh AnchorEntity at move-end, justified as "keeps the anchor tied to the
    // tracked plane" — false: place()'s anchor is AnchorEntity(world:), a fixed
    // world transform, not a child of the plane anchor, and the swap used the
    // same kind. It bought nothing and its removeFromParent()/preservingWorldTransform
    // sequence was actually broken (doubled every drag, added 2.5cm per grab-release
    // — see DECISIONS.md/GESTURE_LOG.md). moveModel() already converts through
    // whatever the current parent is regardless of offset, so there's nothing to fix
    // by re-anchoring. Deleted, not patched.

    /// Removes every placed object, not just the active one.
    func clearAll() {
        for anchor in placedAnchors {
            arView.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
        placedModels.removeAll()
        activeModel = nil
        unhighlightedMaterials = nil
    }
}
