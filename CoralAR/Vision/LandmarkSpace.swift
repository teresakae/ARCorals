import CoreGraphics
import Foundation
import Vision

/// Sole coordinate-conversion site: Vision → image-norm → viewport via displayTransform.
enum LandmarkSpace {
    /// ⚠️ `.right` Vision upright ≠ landscape displayTransform — axis-swap, not y-flip (AGENTS #1–3).
    static func visionToImageNormalized(_ vision: CGPoint) -> CGPoint {
        CGPoint(x: 1 - vision.y, y: 1 - vision.x)
    }

    /// Vision-normalized → image pixels (upper-left origin). Prefer for overlay diagnostics.
    static func visionToImagePixels(_ vision: CGPoint, imageSize: CGSize) -> CGPoint {
        let normalized = NormalizedPoint(x: vision.x, y: vision.y)
        return normalized.toImageCoordinates(imageSize, origin: .upperLeft)
    }

    /// Vision-normalized → viewport pixels using a transform snapshotted with the ARFrame.
    static func visionToViewport(
        _ vision: CGPoint,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let imageNorm = visionToImageNormalized(vision)
        let viewNorm = imageNorm.applying(displayTransform)
        return CGPoint(
            x: viewNorm.x * viewportSize.width,
            y: viewNorm.y * viewportSize.height
        )
    }
}
