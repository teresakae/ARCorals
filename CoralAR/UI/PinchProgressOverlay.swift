import SwiftUI

/// User-facing pinch feedback: a marker at the pinch point once a hand is seen, filling into a
/// ring while the pinch commits (`PinchStateMachine`'s `.pendingBegan` hysteresis window), solid
/// once committed. Always on — gated only by "is a hand currently visible" (`pinchViewportPoint`
/// non-nil), never by a debug toggle. See docs/GESTURES.md §2.5, `PinchStateMachine.pendingProgress`.
struct PinchProgressOverlay: View {
    let pinchViewportPoint: CGPoint?
    /// 0–1: builds during pendingBegan, 1 once the pinch has committed (active/pendingEnd).
    let progress: Double

    private let ringDiameter: CGFloat = 40
    private let dotDiameter: CGFloat = 8

    var body: some View {
        if let point = pinchViewportPoint {
            ZStack {
                // Faint track so the ring's shape reads before any fill.
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 3)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress >= 1 ? Color.green : Color.white,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .rotationEffect(.degrees(-90))

                // "System sees my hand" marker — visible even at progress 0.
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: dotDiameter, height: dotDiameter)
            }
            .position(point)
            .allowsHitTesting(false)
            .animation(.linear(duration: 0.05), value: progress)
        }
    }
}
