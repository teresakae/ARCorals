import Foundation

enum ManipulationMode: String, Equatable, Sendable {
    case ambiguous
    case scale
    case yaw
}

/// Snapshot applied to the child ModelEntity after each update.
struct ManipulationResult: Equatable, Sendable {
    let mode: ManipulationMode
    /// Absolute uniform scale to write, or nil while frozen / non-scale.
    let scale: Float?
    /// Absolute Y-yaw radians to write, or nil while frozen / non-yaw.
    let appliedYaw: Float?
    /// True on the frame mode first locks.
    let didLock: Bool
    let baselineRatio: Double?
    let baselineYaw: Double?
    let accumulatedYaw: Double
    let scaleProgress: Double
    let yawProgress: Double
    let scaleFactor: Float?
    /// True once dwell-to-commit has frozen the gesture (see GestureTuning.dwellDuration).
    let committed: Bool
}

/// Mode-lock + baseline + yaw unwrap for one held pinch. Separate from PinchStateMachine.
struct ManipulationTracker: Sendable {
    var tuning: GestureTuning

    private(set) var mode: ManipulationMode = .ambiguous
    private(set) var isActive = false

    // Settling (pre-lock arming) ≠ dwell-to-commit (post-lock freeze). docs/ARCHITECTURE.md §4
    private(set) var isArmed = false
    private var settleWindow: [Double] = []
    private var settleQuietRun = 0
    private var settleStart: TimeInterval?

    private var yawSamples: [Double] = []
    private var baselineRatio: Double?
    private var baselineYaw: Double?
    /// Lock-rebase trailing samples (median, not the spike lock frame). docs/ARCHITECTURE.md §4
    private var lockRatioSamples: [Double] = []
    private var lockYawSamples: [Double] = []

    private var previousYaw: Double?
    private var accumulatedYaw: Double = 0

    private var entityScale0: Float = 1
    private var entityYaw0: Float = 0
    private var pendingScale: Float = 1
    private var pendingYaw: Float = 0
    /// True → skip the scale-vs-yaw race entirely and commit straight to `.yaw` after arming.
    /// Used by the re-grab-rotate path when scale must never win (docs/GESTURES.md §1).
    private var yawOnly = false
    /// True → skip the scale-vs-yaw race entirely and commit straight to `.scale` after arming.
    /// Mirror of `yawOnly`, opposite mode. Used by Adjust A (finger-spread scale test mode) so
    /// yaw can never win now that yaw lives entirely in `.rotate` (docs/GESTURES.md §1).
    private var scaleOnly = false

    // Dwell-to-commit: hold control signal still for `dwellDuration` → freeze. docs/GESTURES.md §2.5
    private(set) var committed = false
    private var dwellAnchor: Double?
    private var dwellStartTime: TimeInterval?
    private var committedScale: Float?
    private var committedYaw: Float?

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func begin(entityScale: Float, entityYaw: Float, yawOnly: Bool = false, scaleOnly: Bool = false) {
        reset()
        isActive = true
        pendingScale = entityScale
        pendingYaw = entityYaw
        entityScale0 = entityScale
        entityYaw0 = entityYaw
        self.yawOnly = yawOnly
        self.scaleOnly = scaleOnly
    }

    mutating func reset() {
        mode = .ambiguous
        isActive = false
        isArmed = false
        settleWindow = []
        settleQuietRun = 0
        settleStart = nil
        yawSamples = []
        lockRatioSamples = []
        lockYawSamples = []
        baselineRatio = nil
        baselineYaw = nil
        previousYaw = nil
        accumulatedYaw = 0
        entityScale0 = 1
        entityYaw0 = 0
        pendingScale = 1
        pendingYaw = 0
        committed = false
        dwellAnchor = nil
        dwellStartTime = nil
        committedScale = nil
        committedYaw = nil
        yawOnly = false
        scaleOnly = false
    }

    /// Prefer ARFrame timestamps for dwell; wall clock default for tests.
    mutating func update(
        ratio: Double?,
        yaw: Double?,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> ManipulationResult {
        guard isActive else {
            return ManipulationResult(
                mode: .ambiguous,
                scale: nil,
                appliedYaw: nil,
                didLock: false,
                baselineRatio: nil,
                baselineYaw: nil,
                accumulatedYaw: 0,
                scaleProgress: 0,
                yawProgress: 0,
                scaleFactor: nil,
                committed: false
            )
        }

        // Committed: hold frozen values until reset().
        if committed {
            return ManipulationResult(
                mode: mode,
                scale: mode == .scale ? committedScale : nil,
                appliedYaw: mode == .yaw ? committedYaw : nil,
                didLock: false,
                baselineRatio: baselineRatio,
                baselineYaw: baselineYaw,
                accumulatedYaw: accumulatedYaw,
                scaleProgress: mode == .scale ? 1 : 0,
                yawProgress: mode == .yaw ? 1 : 0,
                scaleFactor: committedScale ?? entityScale0,
                committed: true
            )
        }

        // ⚠️ Unwrap yaw before arming — settle-gated accum discarded grab-and-turn. docs/GESTURES.md §2.4
        unwrapYaw(yaw)

        // Settling waits for quiet ratio; yaw already unwrapping above. docs/GESTURES.md §2.4
        if !isArmed {
            arm(ratio: ratio, yaw: yaw, now: now)
            if !isArmed {
                return frozen(didLock: false, scaleProgress: 0, yawProgress: 0)
            }
        }

        // ⚠️ Yaw baseline independent of ratio — co-gating stalled on lag ("stuck ambiguous").
        if baselineYaw == nil, let yaw {
            yawSamples.append(yaw)
            if yawSamples.count >= 3 {
                baselineYaw = Self.median(yawSamples)
                // Deadzone measures motion after baseline is established.
                accumulatedYaw = 0
                previousYaw = yaw
            }
        }

        var didLock = false

        if mode == .ambiguous {
            guard let baselineRatio, let ratio else {
                return frozen(didLock: false, scaleProgress: 0, yawProgress: 0)
            }

            // Trailing window for lock-rebase median.
            lockRatioSamples.append(ratio)
            if lockRatioSamples.count > 3 { lockRatioSamples.removeFirst() }
            if let yaw {
                lockYawSamples.append(yaw)
                if lockYawSamples.count > 3 { lockYawSamples.removeFirst() }
            }

            let scaleProgress = abs(log(ratio / baselineRatio)) / max(tuning.scaleDeadzoneLog, 1e-6)
            let yawProgress = abs(accumulatedYaw) / max(tuning.yawDeadzoneRad, 1e-6)

            // yawOnly/scaleOnly: no race — commit straight to the forced mode the instant
            // arming is done, the opposing channel never wins (docs/GESTURES.md §1).
            if yawOnly || scaleOnly || scaleProgress >= 1 || yawProgress >= 1 {
                if yawOnly {
                    mode = .yaw
                } else if scaleOnly {
                    mode = .scale
                } else if scaleProgress >= yawProgress {
                    // Tie-break: higher progress wins; equal → scale.
                    mode = .scale
                } else {
                    mode = .yaw
                }
                // Rebase baselines at lock (median trailing) so the object doesn't jump.
                self.baselineRatio = Self.median(lockRatioSamples)
                self.baselineYaw = lockYawSamples.isEmpty ? self.baselineYaw : Self.median(lockYawSamples)
                accumulatedYaw = 0
                if let yaw { previousYaw = yaw }
                entityScale0 = pendingScale
                entityYaw0 = pendingYaw
                didLock = true
            } else {
                return frozen(didLock: false, scaleProgress: scaleProgress, yawProgress: yawProgress)
            }
        }

        switch mode {
        case .ambiguous:
            return frozen(didLock: didLock, scaleProgress: 0, yawProgress: 0)

        case .scale:
            guard let ratio, let br = self.baselineRatio else {
                return frozen(didLock: didLock, scaleProgress: 1, yawProgress: 0)
            }
            // Asymmetric scale gain — closing has less travel left. docs/GESTURES.md §2.2
            let logRatio = log(ratio / br)
            let sensitivity = logRatio < 0 ? tuning.scaleShrinkSensitivity : tuning.scaleSensitivity
            let factor = exp(logRatio * sensitivity)
            let absolute = min(max(entityScale0 * Float(factor), 0.25), 4.0)

            if trackDwell(signal: ratio, now: now, threshold: tuning.dwellLogThreshold, isLog: true) {
                committedScale = absolute
            }

            return ManipulationResult(
                mode: .scale,
                scale: absolute,
                appliedYaw: nil,
                didLock: didLock,
                baselineRatio: br,
                baselineYaw: self.baselineYaw,
                accumulatedYaw: accumulatedYaw,
                scaleProgress: 1,
                yawProgress: 0,
                scaleFactor: absolute,
                committed: committed
            )

        case .yaw:
            let applied = entityYaw0 + Float(accumulatedYaw * tuning.yawSensitivity)

            if trackDwell(signal: accumulatedYaw, now: now, threshold: tuning.dwellYawThreshold, isLog: false) {
                committedYaw = applied
            }

            return ManipulationResult(
                mode: .yaw,
                scale: nil,
                appliedYaw: applied,
                didLock: didLock,
                baselineRatio: self.baselineRatio,
                baselineYaw: self.baselineYaw,
                accumulatedYaw: accumulatedYaw,
                scaleProgress: 0,
                yawProgress: 1,
                scaleFactor: entityScale0,
                committed: committed
            )
        }
    }

    /// Bypass dwell and freeze now (OK-sign pause path; unused live). docs/GESTURES.md §2.6
    mutating func forceCommit(scale: Float?, yaw: Float?) {
        guard isActive, !committed else { return }
        committed = true
        committedScale = scale
        committedYaw = yaw
    }

    /// Shared dwell detector for scale/yaw; true on the commit frame.
    private mutating func trackDwell(
        signal: Double,
        now: TimeInterval,
        threshold: Double,
        isLog: Bool
    ) -> Bool {
        guard let anchor = dwellAnchor, let start = dwellStartTime else {
            dwellAnchor = signal
            dwellStartTime = now
            return false
        }
        let moved = isLog ? abs(log(signal / anchor)) : abs(signal - anchor)
        if moved > threshold {
            dwellAnchor = signal
            dwellStartTime = now
            return false
        } else if now - start >= tuning.dwellDuration {
            committed = true
            return true
        }
        return false
    }

    /// Arm after 3 quiet ratio samples (or `settleTimeout`) = baseline. docs/ARCHITECTURE.md §4
    private mutating func arm(ratio: Double?, yaw: Double?, now: TimeInterval) {
        if settleStart == nil { settleStart = now }
        // Prefill yaw samples during settle so yaw doesn't lose the mode-lock race to scale.
        if let yaw {
            yawSamples.append(yaw)
            if yawSamples.count > 3 { yawSamples.removeFirst() }
        }
        if let ratio {
            if let previous = settleWindow.last, abs(log(ratio / previous)) > tuning.settleQuietLogDelta {
                settleQuietRun = 0
            } else if !settleWindow.isEmpty {
                settleQuietRun += 1
            }
            settleWindow.append(ratio)
            if settleWindow.count > 3 { settleWindow.removeFirst() }
        }
        let timedOut = now - (settleStart ?? now) >= tuning.settleTimeout
        guard settleQuietRun >= 2 || (timedOut && !settleWindow.isEmpty) else { return }
        isArmed = true
        baselineRatio = Self.median(settleWindow)
        if !yawSamples.isEmpty {
            baselineYaw = Self.median(yawSamples)
            // Keep settle-window yaw accum into the race — do not zero here. docs/GESTURES.md §2.4
        }
    }

    // ⚠️ Plain delta, not ±π unwrap — `horizontalSlide` isn't periodic (GESTURES.md §2.3).
    private mutating func unwrapYaw(_ yaw: Double?) {
        guard let yaw else { return }
        if let previousYaw {
            accumulatedYaw += yaw - previousYaw
        }
        previousYaw = yaw
    }

    private func frozen(didLock: Bool, scaleProgress: Double, yawProgress: Double) -> ManipulationResult {
        ManipulationResult(
            mode: mode,
            scale: nil,
            appliedYaw: nil,
            didLock: didLock,
            baselineRatio: baselineRatio,
            baselineYaw: baselineYaw,
            accumulatedYaw: accumulatedYaw,
            scaleProgress: scaleProgress,
            yawProgress: yawProgress,
            scaleFactor: entityScale0,
            committed: committed
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
