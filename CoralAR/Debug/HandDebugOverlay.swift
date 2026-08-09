import SwiftUI

/// Debug: mapped pinch point (cyan) + projected raycast hit (yellow). Misalignment = gap between them.
struct HandDebugOverlay: View {
    let pinchViewportPoint: CGPoint?
    let raycastViewportPoint: CGPoint?

    var body: some View {
        Canvas { context, _ in
            if let p = pinchViewportPoint {
                drawCrosshair(context: &context, at: p, color: .cyan, label: "pinch")
            }
            if let r = raycastViewportPoint {
                drawCrosshair(context: &context, at: r, color: .yellow, label: "ray")
                if let p = pinchViewportPoint {
                    var path = Path()
                    path.move(to: p)
                    path.addLine(to: r)
                    context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawCrosshair(context: inout GraphicsContext, at p: CGPoint, color: Color, label: String) {
        let arm: CGFloat = 14
        var h = Path()
        h.move(to: CGPoint(x: p.x - arm, y: p.y))
        h.addLine(to: CGPoint(x: p.x + arm, y: p.y))
        var v = Path()
        v.move(to: CGPoint(x: p.x, y: p.y - arm))
        v.addLine(to: CGPoint(x: p.x, y: p.y + arm))
        context.stroke(h, with: .color(color), lineWidth: 2)
        context.stroke(v, with: .color(color), lineWidth: 2)
        let ring = Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        context.stroke(ring, with: .color(color), lineWidth: 1.5)
        context.draw(
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color),
            at: CGPoint(x: p.x + 10, y: p.y - 14),
            anchor: .topLeading
        )
    }
}

/// 21 landmark dots already mapped to viewport pixels.
struct LandmarkDotsOverlay: View {
    let viewportJoints: [(point: CGPoint, confidence: Float)]

    var body: some View {
        Canvas { context, _ in
            for joint in viewportJoints {
                let color: Color = {
                    if joint.confidence >= 0.7 { return .green }
                    if joint.confidence >= 0.3 { return .yellow }
                    return .red
                }()
                let rect = CGRect(x: joint.point.x - 4, y: joint.point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
    }
}
