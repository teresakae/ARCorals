import RealityKit
import simd
import CoreGraphics
import UIKit

/// Owns placed entities. Scale/yaw go on the child ModelEntity, never the anchor.
@MainActor
final class SceneController {
    private let arView: ARView
    private(set) var placedAnchors: [AnchorEntity] = []
    private(set) var placedModels: [ModelEntity] = []
    /// Entity Adjust/Move act on; place()/selectModel(at:) hit-test reassigns (docs/GESTURES.md §2.1).
    private(set) var activeModel: ModelEntity?
    /// World-Y yaw from activeModel quat each read — not a stored field (docs/GESTURES.md §2.8).
    var modelYaw: Float {
        guard let model = activeModel else { return 0 }
        let q = model.transform.rotation.vector
        return 2 * atan2(q.y, q.w)
    }
    /// Saved materials before setHighlighted(true); nil when not highlighted.
    private var unhighlightedMaterials: [Material]?

    /// Annotation markers for selectAnnotation(at:) — parallel to placedModels / selectModel.
    private var annotationEntities: [ObjectIdentifier: AnnotationID] = [:]
    private var annotationMarkers: [ModelEntity] = []
    /// Cube-prototype: one test annotation on first placed cube (docs/GESTURES.md §2.9).
    private var didPlaceTestAnnotation = false
    static let testAnnotationID = AnnotationID("Test annotation — coral fact goes here.")
    /// ⚠️ Screen-pt fat grab after `entity(at:)` miss. Same unit class as `waveProximityRadiusPt`. Ad-hoc; docs/GESTURES.md §2.1 / §3.
    static let screenGrabRadiusPt: CGFloat = 220

    /// Pest markers for selectPest(at:) — parallel to annotationEntities / selectAnnotation.
    private var pestEntities: Set<ObjectIdentifier> = []
    private var pestMarkers: [ModelEntity] = []
    /// Sim-mode pest content: pests spawn once, on the first placed cube (O1 stand-in).
    private var didPlacePests = false
    static let pestCount = 3

    var hasPlacedEntity: Bool { activeModel != nil }

    init(arView: ARView) {
        self.arView = arView
    }

    /// Appends a new object and makes it active; caller clears if needed (ADR-019).
    func place(at worldTransform: simd_float4x4) {
        // Position only + identity rot — estimatedPlane normals tilt anchors (docs/GESTURES.md §2.1).
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

        if !didPlaceTestAnnotation {
            // Top face (Y-up) — [0,0,halfHeight] was +Z side, invisible from overhead.
            addAnnotation(Self.testAnnotationID, on: model, relativePosition: [0, ModelProvider.halfHeight, 0])
            didPlaceTestAnnotation = true
        }

        if !didPlacePests {
            spawnPests(on: model)
            didPlacePests = true
        }
    }

    /// Spawns pest markers as pinchable children of O1 (docs/GESTURES.md pest content).
    /// Same shape as `addAnnotation`: small visible mesh + oversized invisible collision.
    @discardableResult
    func spawnPests(on model: ModelEntity, count: Int = SceneController.pestCount) -> [ModelEntity] {
        let markerRadius: Float = 0.006
        // Same ad-hoc hitRadius as annotations (docs/GESTURES.md §3) — well past the visual size.
        let hitRadius: Float = 0.035
        // A few distinct points around the cube's surface so each pest is individually pinchable.
        let positions: [SIMD3<Float>] = [
            [ModelProvider.halfHeight, 0, 0],
            [0, 0, ModelProvider.halfHeight],
            [-ModelProvider.halfHeight, 0, 0]
        ]
        var material = SimpleMaterial()
        material.color = .init(tint: .systemRed, texture: nil)

        var pests: [ModelEntity] = []
        for i in 0..<min(count, positions.count) {
            let pest = ModelEntity(mesh: .generateSphere(radius: markerRadius), materials: [material])
            pest.name = "pest-\(i)"
            pest.position = positions[i]
            pest.collision = CollisionComponent(shapes: [.generateSphere(radius: hitRadius)])
            model.addChild(pest)
            pestEntities.insert(ObjectIdentifier(pest))
            pestMarkers.append(pest)
            pests.append(pest)
        }
        return pests
    }

    /// `entity(at:)` then nearest projected pest within `screenGrabRadiusPt` — pest-only registry,
    /// so a pinch that lands on a pest never resolves to O1 via the parent-walk (docs/GESTURES.md pest content).
    func selectPest(at viewportPoint: CGPoint) -> ModelEntity? {
        if let hit = arView.entity(at: viewportPoint) {
            var candidate: Entity? = hit
            while let entity = candidate {
                if let model = entity as? ModelEntity, pestEntities.contains(ObjectIdentifier(model)) {
                    return model
                }
                candidate = entity.parent
            }
        }
        return nearestEntity(to: viewportPoint, in: pestMarkers)
    }

    /// Write pest world position through its parent — same no-re-anchor pattern as `moveModel` (ADR-019).
    func movePest(_ pest: ModelEntity, toWorld world: SIMD3<Float>) {
        guard let parent = pest.parent else { return }
        pest.position = parent.convert(position: world, from: nil)
    }

    /// Fade to transparent, then remove. Opacity animation verified available on this SDK
    /// (`OpacityComponent` + `FromToByAnimation<Float>` bound to `.opacity`, iOS 18+).
    func removePest(_ pest: ModelEntity, fadeDuration: TimeInterval = 0.5) {
        pestEntities.remove(ObjectIdentifier(pest))
        pestMarkers.removeAll { $0 === pest }

        pest.components.set(OpacityComponent(opacity: 1))
        let fade = FromToByAnimation<Float>(from: 1, to: 0, duration: fadeDuration, bindTarget: .opacity)
        if let resource = try? AnimationResource.generate(with: fade) {
            pest.playAnimation(resource)
        }
        // DispatchQueue, not Task — a plain closure has no Sendable requirement, so capturing
        // this non-Sendable Entity across the delay needs no workaround.
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            pest.removeFromParent()
        }
    }

    /// Child marker for selectAnnotation(at:); hitbox oversized (docs/GESTURES.md §2.9).
    @discardableResult
    func addAnnotation(_ id: AnnotationID, on model: ModelEntity, relativePosition: SIMD3<Float>) -> ModelEntity {
        let markerRadius: Float = 0.006
        // ⚠️ hitRadius 0.035m ad-hoc (HIG ~4.4cm too tight); provisional — docs/GESTURES.md §3.
        let hitRadius: Float = 0.035
        var material = SimpleMaterial()
        material.color = .init(tint: .systemYellow, texture: nil)
        let marker = ModelEntity(mesh: .generateSphere(radius: markerRadius), materials: [material])
        marker.name = "annotation-\(id.rawValue)"
        marker.position = relativePosition
        marker.collision = CollisionComponent(shapes: [.generateSphere(radius: hitRadius)])
        model.addChild(marker)
        annotationEntities[ObjectIdentifier(marker)] = id
        annotationMarkers.append(marker)
        return marker
    }

    /// `entity(at:)` then nearest projected marker within `screenGrabRadiusPt` (docs/GESTURES.md §2.9).
    func selectAnnotation(at viewportPoint: CGPoint) -> AnnotationID? {
        if let hit = arView.entity(at: viewportPoint) {
            var candidate: Entity? = hit
            while let entity = candidate {
                if let id = annotationEntities[ObjectIdentifier(entity)] {
                    return id
                }
                candidate = entity.parent
            }
        }
        guard let marker = nearestEntity(to: viewportPoint, in: annotationMarkers) else { return nil }
        return annotationEntities[ObjectIdentifier(marker)]
    }

    /// `entity(at:)` then nearest projected cube within `screenGrabRadiusPt` (docs/GESTURES.md §2.1).
    @discardableResult
    func selectModel(at viewportPoint: CGPoint) -> ModelEntity? {
        if let hit = arView.entity(at: viewportPoint) {
            var candidate: Entity? = hit
            while let entity = candidate {
                if let model = entity as? ModelEntity, placedModels.contains(model) {
                    activeModel = model
                    return model
                }
                candidate = entity.parent
            }
        }
        guard let model = nearestEntity(to: viewportPoint, in: placedModels) else { return nil }
        activeModel = model
        return model
    }

    /// Screen-space nearest within `screenGrabRadiusPt`. Nil if all off-screen or outside radius.
    private func nearestEntity<E: Entity>(to viewportPoint: CGPoint, in entities: [E]) -> E? {
        var best: (entity: E, dist: CGFloat)?
        for entity in entities {
            guard let projected = arView.project(entity.position(relativeTo: nil)) else { continue }
            let d = hypot(projected.x - viewportPoint.x, projected.y - viewportPoint.y)
            guard d <= Self.screenGrabRadiusPt else { continue }
            if best == nil || d < best!.dist {
                best = (entity, d)
            }
        }
        return best?.entity
    }

    /// Material grab highlight — HoverEffectComponent never fires here (docs/GESTURES.md §2.7).
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
        // Keep base on plane: scale is about centre — shift y by Δhalf-height (docs/GESTURES.md §2.1).
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

    /// Write child world position through parent; no re-anchor (docs/GESTURES.md §2.8 / ADR-019).
    func moveModel(toWorld world: SIMD3<Float>) {
        guard let model = activeModel, let parent = model.parent else { return }
        model.position = parent.convert(position: world, from: nil)
    }

    // ponytail: end-of-move re-anchor deleted — doubled drag + 2.5cm/release (ADR-019).

    /// Removes every placed object, not just the active one.
    func clearAll() {
        for anchor in placedAnchors {
            arView.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
        placedModels.removeAll()
        activeModel = nil
        unhighlightedMaterials = nil
        annotationEntities.removeAll()
        annotationMarkers.removeAll()
        didPlaceTestAnnotation = false
        pestEntities.removeAll()
        pestMarkers.removeAll()
        didPlacePests = false
    }
}
