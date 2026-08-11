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

    // Phase 5 — mirrored from CoralAR for ManipulationTracker unit tests.
    var scaleDeadzoneLog: Double = 0.22
    var yawDeadzoneRad: Double = 0.21
    var scaleSensitivity: Double = 1.0
    var scaleShrinkSensitivity: Double = 1.75
    var yawSensitivity: Double = 1.0
    var scaleModeExitThreshold: Double = 3.5

    // Settling window — mirrored from CoralAR (see CoralAR/Gesture/GestureTuning.swift).
    var settleQuietLogDelta: Double = 0.06
    var settleTimeout: TimeInterval = 0.6

    // Dwell-to-commit — mirrored from CoralAR (see CoralAR/Gesture/GestureTuning.swift).
    var dwellLogThreshold: Double = 0.05
    var dwellYawThreshold: Double = 0.05
    var dwellDuration: TimeInterval = 0.4

    // OK-sign (pause/stop) detection — mirrored from CoralAR/Gesture/GestureTuning.swift.
    var okSignFingerExtendedRatio: Double = 1.2

    // Move (Prompt 11) — mirrored from CoralAR for MoveController unit tests.
    var regrabWindow: TimeInterval = 0.4
    var moveSmoothing: Float = 1.0

    // Point — mirrored from CoralAR for PointStateMachine unit tests (see
    // CoralAR/Gesture/GestureTuning.swift).
    var pointDwellDuration: TimeInterval = 0.4

    // Carry — mirrored from CoralAR for CarryStateMachine unit tests.
    var carryToggleMaxDuration: TimeInterval = 0.5

    // Wave — mirrored from CoralAR for WaveDetector unit tests (see
    // CoralAR/Gesture/GestureTuning.swift).
    var waveWindow: TimeInterval = 1.0
    var waveMinReversals: Int = 3
    var waveMinAmplitude: Double = 0.05
    var waveHoldDuration: TimeInterval = 2.0
    var waveProgressDecay: TimeInterval = 2.5
    var waveStationaryRadius: Double = 0.02
    var waveCooldownDuration: TimeInterval = 2.0

    var pinchEnterThreshold: Double { pinchThreshold - hysteresisBand / 2 }
    var pinchExitThreshold: Double { pinchThreshold + hysteresisBand / 2 }
}
