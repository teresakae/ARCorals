import SwiftUI

/// Placeholder floating target for Point mode, ported from posehandtest's `ControlPanelView`
/// (`Layer 1 — 2D UI` in its `PointerInteractionResolver`). Purely a test surface for the
/// hand-tracking hit-test/dwell logic — it's the fingertip that "presses" this, not a real
/// touch, so it stays `.allowsHitTesting(false)` and reports its frame back for
/// `ARSessionCoordinator.testButtonFrame` to hit-test against.
struct PointTestButton: View {
    /// Hit right now, before dwell completes — drives the live progress ring.
    let isHovering: Bool
    /// Latched by `.hoverBegan` — dwell already fired.
    let isSelected: Bool
    let dwellProgress: Double
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.title2)
            Text("Test Button")
                .font(.caption.weight(.semibold))
        }
        .frame(width: 120, height: 90)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.green.opacity(0.85) : (isHovering ? Color.orange.opacity(0.75) : Color.gray.opacity(0.6)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .trim(from: 0, to: isHovering ? dwellProgress : 0)
                .stroke(Color.white, lineWidth: 3)
                .animation(.linear(duration: 0.05), value: dwellProgress)
        )
        // Geometry reported BEFORE the scale so the hit-test rect matches the resting (not
        // scaled-up) visual — scaleEffect is render-only and doesn't move the layout frame.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrameChange($0) }
        .scaleEffect(isHovering ? 1.08 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .allowsHitTesting(false)
    }
}
