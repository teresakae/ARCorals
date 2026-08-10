import RealityKit
import UIKit

/// Returns the ModelEntity to place. Phase 3–5: generated cube. Phase 6: coral.usdz.
@MainActor
enum ModelProvider {
    /// Half the placeholder's height — the lift that keeps its base on the
    /// plane (the box mesh is centred on the entity origin). Scales with the
    /// entity, so anything positioning it has to multiply by current scale.
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
