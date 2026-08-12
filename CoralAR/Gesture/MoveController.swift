import Foundation
import simd

/// Move vs Adjust by re-grab timing only — never race signals. docs/GESTURES.md §2.8
enum GrabTrigger: Equatable, Sendable {
    case move
    case adjust
}

/// Fresh grab (≥`regrabWindow`) → move; quick re-pinch → adjust. Dead live. docs/GESTURES.md §2.8
func moveOrAdjustTrigger(
    now: TimeInterval,
    lastGestureEnd: TimeInterval?,
    regrabWindow: TimeInterval
) -> GrabTrigger {
    guard let lastGestureEnd else { return .move }
    return (now - lastGestureEnd) < regrabWindow ? .adjust : .move
}

/// Absolute-from-grab via placement-preview raycast; separate from ManipulationTracker.
struct MoveController {
    var tuning: GestureTuning

    private(set) var isActive = false
    private var hit0: SIMD3<Float> = .zero
    private var model0: SIMD3<Float> = .zero
    /// EMA-smoothed target world position, written every `.changed` frame.
    private(set) var target: SIMD3<Float> = .zero

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func begin(hit: SIMD3<Float>, modelWorld: SIMD3<Float>) {
        isActive = true
        hit0 = hit
        model0 = modelWorld
        target = modelWorld
    }

    /// `model0 + (hit - hit0)`, EMA; nil hit holds last target.
    @discardableResult
    mutating func update(hit: SIMD3<Float>?) -> SIMD3<Float> {
        guard isActive, let hit else { return target }
        let raw = model0 + (hit - hit0)
        target = simd_mix(target, raw, SIMD3<Float>(repeating: tuning.moveSmoothing))
        return target
    }

    mutating func reset() {
        isActive = false
        hit0 = .zero
        model0 = .zero
        target = .zero
    }
}
