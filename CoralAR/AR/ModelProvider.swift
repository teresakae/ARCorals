import RealityKit
import UIKit

/// Returns the ModelEntity to place. Phase 3–5: generated cube. Phase 6: coral.usdz.
@MainActor
enum ModelProvider {
    /// Half-height base lift (mesh origin-centred); × current scale. GESTURES.md flush-on-plane.
    static let halfHeight: Float = 0.025

    /// 5 cm cube — plain placeholder until Phase 6.
    static func makePlaceholder() -> ModelEntity {
        let mesh = MeshResource.generateBox(size: halfHeight * 2, cornerRadius: 0.002)
        var material = SimpleMaterial()
        material.color = .init(tint: .systemTeal, texture: nil)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "placeholderCube"
        entity.generateCollisionShapes(recursive: true)
        return entity
    }
}
