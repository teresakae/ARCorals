import CoreGraphics
import Foundation
import Vision

/// Only place coordinate conversion happens.
/// Vision bottom-left → image top-left normalized → viewport pixels via `displayTransform`.
enum LandmarkSpace {
    /// Vision-normalized (bottom-left, `.right`-oriented/upright) → camera-image-normalized
    /// (upper-left, native landscape). `ARFrame.displayTransform` expects the native landscape
    /// image space, not the upright space Vision returns when run with `orientation: .right`
    /// (AGENTS gotcha #2 + #3) — this needs the axis swap, not just the y-flip.
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
