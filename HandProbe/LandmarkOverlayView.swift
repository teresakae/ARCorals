import SwiftUI
import Vision

struct LandmarkOverlayView: View {
    let joints: [JointSample]
    let orientedImageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard orientedImageSize.width > 0, orientedImageSize.height > 0 else { return }
                for joint in joints {
                    let pt = Self.viewPoint(
                        normalizedBottomLeft: CGPoint(x: joint.x, y: joint.y),
                        imageSize: orientedImageSize,
                        viewSize: size
                    )
                    let color = Self.color(for: joint.confidence)
                    let rect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Vision normalized (bottom-left) → upright image pixels (upper-left) → aspect-fill view.
    static func viewPoint(
        normalizedBottomLeft: CGPoint,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGPoint {
        let normalized = NormalizedPoint(x: normalizedBottomLeft.x, y: normalizedBottomLeft.y)
        let imagePoint = normalized.toImageCoordinates(imageSize, origin: .upperLeft)
        return aspectFill(imagePoint: imagePoint, imageSize: imageSize, viewSize: viewSize)
    }

    static func aspectFill(imagePoint: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let xOffset = (viewSize.width - scaled.width) / 2
        let yOffset = (viewSize.height - scaled.height) / 2
        return CGPoint(
            x: imagePoint.x * scale + xOffset,
            y: imagePoint.y * scale + yOffset
        )
    }

    static func color(for confidence: Float) -> Color {
        if confidence >= 0.7 { return .green }
        if confidence >= 0.3 { return .yellow }
        return .red
    }
}
