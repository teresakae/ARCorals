import CoreGraphics
import Foundation
import UIKit
import Vision

/// Sole coordinate-conversion site: Vision → viewport, aspect-fill. Ported from posehandtest's
/// `PointerCoordinateMapper` — the version verified on device — after `ARFrame.displayTransform`
/// composed with a cached SwiftUI viewport size turned out to disagree with where RealityKit's
/// `ARView` actually draws the camera feed (see chat: crosshair offset investigation). No
/// `displayTransform`, no cached size: `viewportSize` must be `arView.bounds.size` read live.
enum LandmarkSpace {
    /// Size of the camera buffer *after* Vision has rotated it upright.
    static func uprightImageSize(_ imageResolution: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: imageResolution.height, height: imageResolution.width)
        default:
            return imageResolution
        }
    }

    /// Vision-normalized (bottom-left origin, upright) → viewport points (top-left origin),
    /// aspect-fill — matches how `ARView` renders the camera feed, so the crosshair stays glued
    /// to the fingertip instead of drifting toward the edges.
    static func visionToViewport(
        _ vision: CGPoint,
        uprightImageSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        guard uprightImageSize.width > 0, uprightImageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return .zero }

        let scale = max(viewportSize.width / uprightImageSize.width,
                         viewportSize.height / uprightImageSize.height)
        let displayed = CGSize(width: uprightImageSize.width * scale,
                                height: uprightImageSize.height * scale)
        let originX = (viewportSize.width - displayed.width) / 2
        let originY = (viewportSize.height - displayed.height) / 2

        return CGPoint(
            x: originX + vision.x * displayed.width,
            y: originY + (1 - vision.y) * displayed.height
        )
    }

    /// `UIInterfaceOrientation` → the Vision `orientation:` that makes `request.perform` see an
    /// upright hand. Table verified against posehandtest's `PointerMapping.swift:82-89`.
    static func visionOrientation(for interfaceOrientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interfaceOrientation {
        case .landscapeRight: return .up
        case .landscapeLeft: return .down
        case .portraitUpsideDown: return .left
        default: return .right // .portrait, .unknown
        }
    }

    /// dy in normalized coords needs this to compare fairly against dx — a horizontal and
    /// vertical span of equal physical length otherwise measure unequal once the buffer isn't
    /// square. Derived from the actual buffer resolution, not a hardcoded 1920×1440 — correct
    /// even if ARKit picks a non-4:3 video format.
    static func dyAspectCorrection(for orientation: CGImagePropertyOrientation, imageResolution: CGSize) -> Double {
        let upright = uprightImageSize(imageResolution, orientation: orientation)
        guard upright.width > 0 else { return 1 }
        return Double(upright.height / upright.width)
    }
}
