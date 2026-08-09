import ARKit
import RealityKit
import CoreGraphics

/// Viewport point → world transform via the raycast fallback chain.
@MainActor
struct PlacementService {
    enum Tier: String, Sendable {
        case existingPlaneGeometry
        case existingPlaneInfinite
        case estimatedPlane
        case none
    }

    struct Result: Sendable {
        let worldTransform: simd_float4x4?
        let tier: Tier
    }

    /// `.existingPlaneGeometry` → `.existingPlaneInfinite` → `.estimatedPlane`.
    func raycast(from viewPoint: CGPoint, in arView: ARView) -> Result {
        let chain: [(ARRaycastQuery.Target, Tier)] = [
            (.existingPlaneGeometry, .existingPlaneGeometry),
            (.existingPlaneInfinite, .existingPlaneInfinite),
            (.estimatedPlane, .estimatedPlane),
        ]

        for (target, tier) in chain {
            let hits = arView.raycast(from: viewPoint, allowing: target, alignment: .horizontal)
            if let hit = hits.first {
                return Result(worldTransform: hit.worldTransform, tier: tier)
            }
        }
        return Result(worldTransform: nil, tier: .none)
    }
}
