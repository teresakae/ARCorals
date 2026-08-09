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

    var pinchEnterThreshold: Double { pinchThreshold - hysteresisBand / 2 }
    var pinchExitThreshold: Double { pinchThreshold + hysteresisBand / 2 }
}
