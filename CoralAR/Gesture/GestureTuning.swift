import Foundation

/// Every magic number in one place. Phase 1 / ADR-015 values — verify transfer on ARFrame (seam #2).
struct GestureTuning: Sendable, Equatable {
    static let `default` = GestureTuning()

    /// palmWidth pinchRatio below this (minus band) → pinch intent.
    /// Source: ADR-017. The HandProbe/ADR-015 value (5.9) did NOT transfer —
    /// ARFrame's 4:3 buffer vs AVCaptureSession's 16:9 shifted the whole
    /// distribution ~46% (phase4_join_20260809_174233.csv: pinched mean 0.823,
    /// open mean 5.490 — at the old 5.9 threshold, 58.9% of open-hand frames
    /// misfired as "pinch began"). Re-derived from that CSV's calibration rows.
    var pinchThreshold: Double = 1.98

    /// Provisional — carried over from ADR-015, NOT re-derived from a clean
    /// static hold on ARFrame (this run was live self-toggled labeling, no
    /// isolated pinch/open hold like HandProbe's b2/b3). Open-hand noise looked
    /// higher here (sd ≈73% of its own mean vs HandProbe's cleaner hold) —
    /// revisit with a real static-hold CSV before trusting this band.
    var hysteresisBand: Double = 1.0
    var hysteresisDuration: TimeInterval = 0.100
    var gracePeriod: TimeInterval = 0.200
    var confidenceGate: Float = 0.3
    var inferenceInterval: TimeInterval = 0.066

    // Phase 5 — provisional; set by targeting runs (TESTING.md Run F).
    /// log(|ratio/baseline|) must reach this before scale can lock.
    var scaleDeadzoneLog: Double = 0.18
    /// |accumulatedYaw| (rad) must reach this before yaw can lock.
    /// Was 0.21 (~12°) — too low, got beaten by incidental wrist rotation
    /// that naturally happens while spreading fingers to scale, so yaw won
    /// the lock almost every time regardless of intent. ~20° gives scale a
    /// fair shot at winning a genuine widen/narrow motion.
    var yawDeadzoneRad: Double = 0.35
    /// Was 1.0 — mapped the ~40x range of real finger motion onto the 16x
    /// scale range almost 1:1, so one real movement slammed the clamp
    /// (measured: lock to 0.25x floor in 130ms on device). 0.5 spreads that
    /// same motion across the usable range instead of a two-position switch.
    var scaleSensitivity: Double = 0.5
    /// Opening-side travel (settled pinch ≈0.64 up to the 3.5 scale-mode exit,
    /// ~1.7 in log) dwarfs closing-side travel (≈0.64 down to a ~0.31 physical
    /// floor, and users stop around 0.4 in log — measured over 87 gestures in
    /// phase5_manip_20260809_23*.csv). At a single sensitivity the deadzone
    /// eats most of the closing budget and "shrink" tops out near 0.9x.
    /// Provisional: 1.75 puts shrink near 0.5x for the same physical motion
    /// that grows ~2x, i.e. roughly symmetric in log-scale. Retune with
    /// scaleSensitivity/scaleDeadzoneLog.
    var scaleShrinkSensitivity: Double = 1.75
    var yawSensitivity: Double = 1.0
    /// Yaw driving signal switched from hand-rotation angle to horizontal
    /// slide of the pinch point (normalized screen-width fraction), per user
    /// call — rotation-by-angle from a short landmark vector kept losing to
    /// scale/noise no matter which vector pair or tuning; a slide is a
    /// position signal, same family as placement's raycast point, robust and
    /// structurally independent from the aperture-based scale signal (shares
    /// no landmarks). Provisional: comfortably slides across ~15-20% of
    /// screen width for a full-range gesture; retune alongside yawDeadzoneRad.
    var horizontalSlideGain: Double = 12.0
    /// Raised exit threshold while scale mode is locked (opening fingers is the scale signal).
    var scaleModeExitThreshold: Double = 3.5

    // Settling window — the grab is one continuous closure and `.began` fires
    // part-way through it, so ManipulationTracker ignores everything (baseline,
    // yaw accumulation, mode-lock race) until the pinch stops moving.
    // Provisional, derived from phase5_manip_20260809_23*.csv (87 gestures,
    // ~15Hz): median per-frame |Δlog(ratio)| runs 0.25 → 0.12 over the first
    // ~150ms after Began, then drops to 0.02–0.03 by ~200–300ms.
    /// Per-frame |Δlog(ratio)| at or under this counts as "quiet"; three
    /// consecutive quiet samples arm the gesture (≈200ms at 15Hz).
    var settleQuietLogDelta: Double = 0.06
    /// Arm anyway after this long if the hand never goes quiet.
    var settleTimeout: TimeInterval = 0.6

    // Dwell-to-commit — hold the control signal ~still this long to freeze
    // the gesture (Fix 3). Provisional, same order of magnitude as the
    // deadzones above; retune alongside them once on-device data exists.
    /// log(ratio/dwellAnchor) must stay under this to count as "still" while scaling.
    var dwellLogThreshold: Double = 0.05
    /// |accumulatedYaw - dwellAnchor| (rad) must stay under this to count as "still" while yawing.
    var dwellYawThreshold: Double = 0.05
    /// Seconds the signal must hold still before the gesture commits.
    var dwellDuration: TimeInterval = 0.4

    var pinchEnterThreshold: Double { pinchThreshold - hysteresisBand / 2 }
    var pinchExitThreshold: Double { pinchThreshold + hysteresisBand / 2 }

    // OK-sign (pause/stop) detection — HandShapeClassifier. Reuses
    // `pinchThreshold` for the thumb-index tightness check (an OK sign's
    // thumb-index geometry is indistinguishable from a normal pinch), so
    // only the finger-extension side needs its own knob.
    /// dist(fingerTip, fingerMCP) / palmWidth above this → finger counted as
    /// "extended". Provisional — picked as a reasonable midpoint (curled
    /// fingers should sit well under 1.0, genuinely extended fingers well
    /// over); no clean on-device calibration data for this specific ratio
    /// exists yet (phase0_detection_sweep_*.csv only logs pinch ratios, not
    /// per-finger tip/MCP distances). Retune once real OK-sign vs.
    /// pinch/grab hold data exists.
    var okSignFingerExtendedRatio: Double = 1.2

    // Move (Prompt 11) — grab-timing trigger, not a signal race against Adjust.
    /// A re-grab within this long of the previous gesture ending is treated
    /// as "still working the object" → Adjust. Longer than this (or no prior
    /// gesture) → Move. Provisional — needs an on-device pass: log
    /// gesture-end-to-next-gesture-start intervals (the CSV already has
    /// timestamps) and pick the value that separates "deliberate quick
    /// re-grab" from "just moved, grabbing again to move more". At ~15Hz
    /// inference (ADR-011), 0.4s is only ~6 frames of margin either side of
    /// the boundary — worth widening once real intervals exist rather than
    /// trusting this guess.
    var regrabWindow: TimeInterval = 0.4
    /// EMA factor for Move's per-frame target position (1.0 = no smoothing,
    /// snaps straight to the raw raycast delta). Provisional.
    var moveSmoothing: Float = 0.5
}
