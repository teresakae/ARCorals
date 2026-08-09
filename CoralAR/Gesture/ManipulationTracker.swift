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

    // Settling window (arming). Distinct from dwell-to-commit below: settling
    // runs BEFORE any baseline/mode-lock exists and asks "has the hand stopped
    // closing yet?" off per-frame rate of change; dwell runs AFTER a mode is
    // locked and asks "has the control signal held near one anchor long
    // enough to freeze?" Different questions, different state, no shared
    // helper worth forcing.
    private(set) var isArmed = false
    private var settleWindow: [Double] = []
    private var settleQuietRun = 0
    private var settleStart: TimeInterval?

    private var yawSamples: [Double] = []
    private var baselineRatio: Double?
    private var baselineYaw: Double?
    /// Trailing samples for the lock-instant rebase — a single frame at lock
    /// is, by definition, likely to be the noise spike that triggered the
    /// lock; median a short trailing window instead.
    private var lockRatioSamples: [Double] = []
    private var lockYawSamples: [Double] = []

    private var previousYaw: Double?
    private var accumulatedYaw: Double = 0

    private var entityScale0: Float = 1
    private var entityYaw0: Float = 0
    private var pendingScale: Float = 1
    private var pendingYaw: Float = 0

    // Dwell-to-commit: once locked, holding the control signal still for
    // tuning.dwellDuration freezes the gesture at its current value.
    private(set) var committed = false
    private var dwellAnchor: Double?
    private var dwellStartTime: TimeInterval?
    private var committedScale: Float?
    private var committedYaw: Float?

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func begin(entityScale: Float, entityYaw: Float) {
        reset()
        isActive = true
        pendingScale = entityScale
        pendingYaw = entityYaw
        entityScale0 = entityScale
        entityYaw0 = entityYaw
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
    }

    /// `now` should be a real, monotonically increasing clock (e.g. ARFrame
    /// timestamp) — dwell-to-commit times off it. Defaults to wall clock so
    /// call sites that don't care (tests) don't have to thread one through.
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

        // Already committed: frozen at the value captured at commit time,
        // regardless of further hand motion, until reset() (gesture end).
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

        // Always unwrap yaw, arming or not — a real grab-and-turn is one
        // continuous motion, not grab-pause-turn. If accumulation only
        // started once armed, a rotation that begins during the settle
        // window (which is common: closing the pinch and starting the turn
        // happen together) would be silently thrown away, and the race
        // would then see no yaw motion at all and lock scale by default.
        unwrapYaw(yaw)

        // Settling window. A natural grab is one continuous fast closure and
        // `.began` fires part-way through it, so the frames right after begin
        // are pinch-closing motion, not scale intent. The RATIO baseline and
        // the mode-lock race wait for the ratio to go quiet (or timeout) —
        // but yaw accumulation above is NOT gated on this, so real rotation
        // that happens while the pinch is still settling still counts.
        if !isArmed {
            arm(ratio: ratio, yaw: yaw, now: now)
            if !isArmed {
                return frozen(didLock: false, scaleProgress: 0, yawProgress: 0)
            }
        }

        // Yaw baseline is established independently of ratio's — the yaw
        // signal's confidence gate (two MCP joints) can lag ratio's by
        // several frames, and gating both together stalls the whole gesture
        // on a single dropped frame (the "stuck ambiguous" bug).
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

            // Keep a short trailing window so the lock-instant rebase medians
            // recent samples instead of trusting the single (likely spiky) frame.
            lockRatioSamples.append(ratio)
            if lockRatioSamples.count > 3 { lockRatioSamples.removeFirst() }
            if let yaw {
                lockYawSamples.append(yaw)
                if lockYawSamples.count > 3 { lockYawSamples.removeFirst() }
            }

            let scaleProgress = abs(log(ratio / baselineRatio)) / max(tuning.scaleDeadzoneLog, 1e-6)
            let yawProgress = abs(accumulatedYaw) / max(tuning.yawDeadzoneRad, 1e-6)

            if scaleProgress >= 1 || yawProgress >= 1 {
                // Tie-break: higher progress wins; equal → scale.
                if scaleProgress >= yawProgress {
                    mode = .scale
                } else {
                    mode = .yaw
                }
                // Rebase at lock so the object does not jump. Median the trailing
                // window rather than the single lock frame — see lockRatioSamples.
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
            // Asymmetric by direction: a settled pinch sits near the physical
            // closing floor, so the closing side has far less travel left than
            // the opening side (see GestureTuning.scaleShrinkSensitivity).
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

    /// Immediately freezes the gesture at the given value, bypassing the
    /// dwell timer — the OK-sign pause override (HandShapeClassifier, via
    /// ARSessionCoordinator) calls this instead of waiting out
    /// tuning.dwellDuration. No-op if not actively locked or already committed.
    mutating func forceCommit(scale: Float?, yaw: Float?) {
        guard isActive, !committed else { return }
        committed = true
        committedScale = scale
        committedYaw = yaw
    }

    /// Shared dwell-still-detector for both the scale (log-ratio) and yaw
    /// (radians) control signals — only one is ever active per locked
    /// gesture, so one anchor/timer pair covers both. Returns true on the
    /// frame commit fires (caller stores its own frozen value that frame).
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

    /// Arms the gesture once the pinch has stopped closing: three consecutive
    /// ratio samples within `settleQuietLogDelta` of each other. The quiet
    /// samples are themselves the baseline (same median-of-3 as before, just
    /// taken from frames that are known-still), so arming costs no extra
    /// frames beyond the settling itself. `settleTimeout` arms anyway if the
    /// hand never goes quiet — a laggy gesture beats a dead one.
    private mutating func arm(ratio: Double?, yaw: Double?, now: TimeInterval) {
        if settleStart == nil { settleStart = now }
        // Yaw rides along so its baseline is ready the instant we arm. Yaw's
        // deadzone needs motion accumulated over several frames to trip; if it
        // also had to spend 3 post-arm frames finding a baseline it would lose
        // the mode-lock race to scale's single-frame check every time.
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
            // previousYaw and accumulatedYaw are NOT reset here — unwrapYaw
            // has been running continuously since .began (see update()), so
            // any real rotation during the settle window is already reflected
            // and must survive into the mode-lock race, not be discarded.
        }
    }

    private mutating func unwrapYaw(_ yaw: Double?) {
        guard let yaw else { return }
        if let previousYaw {
            let delta = atan2(sin(yaw - previousYaw), cos(yaw - previousYaw))
            accumulatedYaw += delta
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
