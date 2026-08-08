import Foundation

/// Every magic number in one place. Phase 1 / ADR-015 values — not guesses.
struct GestureTuning: Sendable, Equatable {
    static let `default` = GestureTuning()

    /// palmWidth pinchRatio below this (minus band) → pinch intent.
    /// Source: ADR-015; confirmed ≈5.91 midpoint of pinched/open means in
    /// `phase1_b1_20260809-0223.csv` at ~40cm. Static holds:
    /// pinched max≈0.91 (`phase1_pinched_static__20260809-0238.csv`),
    /// open min≈6.42 (`phase1_b3_opened_20260809-0227.csv`).
    var pinchThreshold: Double = 5.9

    /// Schmitt-trigger half-gap around the threshold (enter at T−band/2, exit at T+band/2).
    /// ≈20% of static open−pinched gap (~5.5) from Phase 1 static holds.
    var hysteresisBand: Double = 1.0

    /// Must stay on the pinched/open side this long before flipping. STEPS Phase 2: ~100ms.
    var hysteresisDuration: TimeInterval = 0.100

    /// Dropped/low-confidence frames tolerated mid-drag. TESTING: survive ≥3 @ ~15Hz.
    var gracePeriod: TimeInterval = 0.200

    var confidenceGate: Float = 0.3

    /// Vision throttle. Matches HandPoseDetector.
    var inferenceInterval: TimeInterval = 0.066

    var pinchEnterThreshold: Double { pinchThreshold - hysteresisBand / 2 }
    var pinchExitThreshold: Double { pinchThreshold + hysteresisBand / 2 }
}
