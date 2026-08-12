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
    /// Gain for the vertical-slide scale signal (Adjust B test mode) — screen-height fraction ×
    /// gain, fed as a plain linear delta the same shape as `horizontalSlideGain`'s yaw signal
    /// (not log-wrapped — a linear screen slide isn't a multiplicative distance ratio; see
    /// docs/GESTURES.md §1/§2.2). Provisional — guessed starting value (a full top-to-bottom
    /// slide should span most of the [0.25, 4.0] scale clamp), pending real device calibration;
    /// no CSV behind this number yet.
    var verticalSlideGain: Double = 3.0
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
    /// Rolling window of raw `isPointing` readings PointStateMachine majority-votes over before
    /// accumulating dwell — tolerates a single usable-but-misclassified frame (weak middle/ring/
    /// little landmark) without conflating it with the grace period's dropped-frame tolerance.
    /// Sized to this project's existing median-of-3 / quiet-run-of-2 smoothing conventions
    /// (`ManipulationTracker.settleWindow`). ad-hoc.
    var pointingWindowSize: Int = 5

    // MARK: - Carry

    /// Pinch began→ended under this = toggle; longer = grab-drag. 0.7s ad-hoc; see docs/GESTURES.md §2.8, §3.
    var carryToggleMaxDuration: TimeInterval = 0.7

    // MARK: - Sim / pest pick-up-and-throw

    /// World-space distance (m) from O1's centre beyond which a released pest fades and is
    /// deleted; within it counts as an accidental near-drop and the pest just stays placed.
    /// Intent is detachment, not distance: the fade should read as "it came off the cube's
    /// surface," not "it got thrown." Set to `ModelProvider.halfHeight` (cube half-size) plus a
    /// small few-cm margin past the surface. Provisional — guessed margin, pending real device
    /// calibration. Content-layer constant, not yet measured on this rig.
    var pestDiscardDistance: Float = 0.045

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

    // MARK: - Bystander-hand rejection (ADR-021)

    /// handCoveragePct() floor — below this, treat as no hand (too small/far, likely background). Placeholder, uncalibrated.
    var handCoverageMin: Double = 0.5
    /// handCoveragePct() ceiling — above this, treat as no hand (implausibly close/large, likely not the tracked hand). Placeholder, uncalibrated.
    var handCoverageMax: Double = 60.0
    /// Max normalized centroid travel accepted between consecutive frames; larger = reject as a different hand. Placeholder, uncalibrated.
    var handJumpRejectRadius: Double = 0.35
}
