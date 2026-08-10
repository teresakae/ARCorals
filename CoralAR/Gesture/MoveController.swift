import Foundation
import simd

/// Which mode a grab (`.began` on an already-placed entity) enters. Decided
/// purely by elapsed time since the last gesture ended — never by racing
/// Move against Adjust's signals. See docs/DECISIONS.md ADR-018 follow-ups:
/// Yaw's horizontal-slide is a projection of Move's own position, so any
/// real move would trigger Yaw's deadzone by construction if the two ever
/// read the same frame's signals.
enum GrabTrigger: Equatable, Sendable {
    case move
    case adjust
}

/// Pure trigger decision, extracted for testing. No prior gesture, or one
/// that ended `regrabWindow` or more ago, means a fresh grab — treated as
/// intent to move. A quick re-pinch inside the window means the user is
/// still working the object they just released — treated as intent to
/// adjust (scale/yaw).
func moveOrAdjustTrigger(
    now: TimeInterval,
    lastGestureEnd: TimeInterval?,
    regrabWindow: TimeInterval
) -> GrabTrigger {
    guard let lastGestureEnd else { return .move }
    return (now - lastGestureEnd) < regrabWindow ? .adjust : .move
}

/// Move-mode state: absolute-from-grab positioning (not accumulated deltas,
/// so per-frame raycast noise doesn't compound). Reads only the pinch
/// point's raycast hit, already computed each frame by
/// ARSessionCoordinator.updateOverlay's live placement-preview line — this
/// costs zero new raycasts. ManipulationTracker is untouched; Move is
/// structurally separate, not a mode case there.
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

    /// Next target = model's position at grab + how far the raycast hit has
    /// moved since grab, EMA-smoothed. `hit == nil` (raycast miss this
    /// frame) holds the last target rather than dropping the grab.
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
