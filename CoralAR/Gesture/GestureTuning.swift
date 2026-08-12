import Foundation

/// Every magic number in one place. Phase 1 / ADR-015 values — verify transfer on ARFrame (seam #2).
struct GestureTuning: Sendable, Equatable {
    static let `default` = GestureTuning()

    /// palmWidth pinchRatio below this → pinch intent. Re-derived per ADR-017; see docs/GESTURES.md §3.
    var pinchThreshold: Double = 1.98

    /// Pinch hysteresis band. Measured — ADR-017 addendum static hold; see docs/GESTURES.md §3.
    var hysteresisBand: Double = 1.0
    var hysteresisDuration: TimeInterval = 0.100
    var gracePeriod: TimeInterval = 0.200
    var confidenceGate: Float = 0.3
    var inferenceInterval: TimeInterval = 0.066

    // Phase 5 mode-lock tuning — provisional; see docs/GESTURES.md §3 for provenance.
    /// log(|ratio/baseline|) must reach this before scale can lock.
    var scaleDeadzoneLog: Double = 0.18
    /// |accumulatedYaw| (rad) to lock yaw. Raised from 0.21 — wrist rotation was winning the race; see docs/GESTURES.md §3.
    var yawDeadzoneRad: Double = 0.35
    /// Scale gain, lowered from 1.0 — was slamming the clamp at ~130ms; see docs/GESTURES.md §2.2.
    var scaleSensitivity: Double = 0.5
    /// Asymmetric shrink gain — closing hits a physical floor sooner; see docs/GESTURES.md §2.2.
    var scaleShrinkSensitivity: Double = 1.75
    var yawSensitivity: Double = 1.0
    /// Gain for horizontal-slide yaw signal. Ad-hoc, shipped/tuned; see docs/GESTURES.md §2.3.
    var horizontalSlideGain: Double = 12.0
    /// Raised exit threshold while scale mode is locked (opening fingers is the scale signal).
    var scaleModeExitThreshold: Double = 3.5

    // Settling window — ignores signal until the pinch stops moving; see docs/GESTURES.md §3.
    /// Per-frame |Δlog(ratio)| ≤ this counts as quiet; 3 consecutive quiet frames arm the gesture (~200ms).
    var settleQuietLogDelta: Double = 0.06
    /// Arm anyway after this long if the hand never goes quiet.
    var settleTimeout: TimeInterval = 0.6

    // Dwell-to-commit — hold signal still to freeze the gesture; see docs/GESTURES.md §2.5.
    /// log(ratio/dwellAnchor) must stay under this to count as "still" while scaling.
    var dwellLogThreshold: Double = 0.05
    /// |accumulatedYaw - dwellAnchor| (rad) must stay under this to count as "still" while yawing.
    var dwellYawThreshold: Double = 0.05
    /// Seconds the signal must hold still before the gesture commits.
    var dwellDuration: TimeInterval = 0.4

    var pinchEnterThreshold: Double { pinchThreshold - hysteresisBand / 2 }
    var pinchExitThreshold: Double { pinchThreshold + hysteresisBand / 2 }

    // OK-sign detection reuses pinchThreshold for thumb-index tightness; see docs/GESTURES.md §2.6.
    /// Extension ratio (tip/MCP ÷ palmWidth) for OK-sign. Placeholder, unused; see docs/GESTURES.md §2.6.
    var okSignFingerExtendedRatio: Double = 1.2

    // Move — pinch-drag moves a placed object; grab-timing trigger, not a signal race (§2.8).
    /// Re-grab window, dead-path Adjust/Move trigger. Placeholder; see docs/GESTURES.md §2.8, §3.
    var regrabWindow: TimeInterval = 0.4
    /// EMA factor for Move/Carry follow (1.0=no smoothing), raised from 0.5; see docs/GESTURES.md §3.
    var moveSmoothing: Float = 1.0

    // MARK: - Point

    /// Dwell time before an annotation popup fires. Placeholder; see docs/GESTURES.md §2.9, §3.
    var pointDwellDuration: TimeInterval = 0.4
    /// Extension ratio for pointing. Same start value as okSign's, separate knob; see docs/GESTURES.md §3.
    var pointFingerExtendedRatio: Double = 1.2

    // MARK: - Carry

    /// Pinch began→ended under this = toggle; longer = grab-drag. 0.7s ad-hoc; see docs/GESTURES.md §2.8, §3.
    var carryToggleMaxDuration: TimeInterval = 0.7

    // MARK: - Wave

    /// Rolling window for reversal/amplitude detection. Placeholder ~1.0s; see docs/GESTURES.md §3.
    var waveWindow: TimeInterval = 1.0
    /// Direction reversals within waveWindow to count as waving. Placeholder; see docs/GESTURES.md §3.
    var waveMinReversals: Int = 3
    /// Peak-to-peak horizontal travel (norm. width) to count as waving. Placeholder; see docs/GESTURES.md §3.
    var waveMinAmplitude: Double = 0.05
    /// Continuous qualifying time to fire `.waved`. Decided at 2.0s, down from an
    /// original 3.0s design spec (undocumented elsewhere); see docs/GESTURES.md §3.
    var waveHoldDuration: TimeInterval = 2.0
    /// Seconds of non-qualifying time to decay full progress to zero. Mid-band pick; see docs/GESTURES.md §3.
    var waveProgressDecay: TimeInterval = 2.5
    /// Stationary-hold radius (norm-x), half of waveMinAmplitude; see docs/GESTURES.md §3.
    var waveStationaryRadius: Double = 0.02
    /// Cooldown after `.waved` fires. Equals waveHoldDuration so a re-wave needs a fresh gesture; see docs/GESTURES.md §3.
    var waveCooldownDuration: TimeInterval = 2.0
}
