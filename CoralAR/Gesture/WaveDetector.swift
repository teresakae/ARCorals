import Foundation

/// Wave / stationary-hold trigger events.
enum WaveEvent: Equatable, Sendable {
    case waved
}

/// One sample from the wrist-position stream.
struct WaveObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    /// Normalized horizontal wrist position. Wrist only — never finger shape.
    /// `nil` on a dropped/gated frame; still feed one so progress can decay.
    let x: Double?
}

/// Wave / stationary-hold lifecycle. Reads wrist x + timestamp only — no
/// pinch/hand-shape input, so it never conflicts with carry/pinch state.
/// Feed observations; collect events.
struct WaveDetector: Sendable {
    var tuning: GestureTuning

    private enum Phase: Equatable {
        case idle
        case waving(since: TimeInterval)
        case cooldown(until: TimeInterval)
    }

    private var phase: Phase = .idle
    /// Accumulated "in-progress" seconds toward `tuning.waveHoldDuration`.
    /// Same timer for both the reversal-wave path and the stationary-hold
    /// fallback — whichever condition is true this frame feeds it.
    private var progress: TimeInterval = 0
    private var lastTimestamp: TimeInterval?
    /// Rolling buffer over `tuning.waveWindow`, copying PinchRatioCalculator's
    /// `RollingMinMax` age-based drop pattern (see that struct's `push`).
    private var buffer: [(t: TimeInterval, x: Double)] = []
    private var stationaryAnchor: Double?

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    @discardableResult
    mutating func process(_ observation: WaveObservation) -> [WaveEvent] {
        let dt: TimeInterval
        if let last = lastTimestamp, observation.timestamp > last {
            dt = observation.timestamp - last
        } else {
            dt = 0
        }
        lastTimestamp = observation.timestamp

        if case .cooldown(let until) = phase {
            if observation.timestamp >= until {
                phase = .idle
            } else {
                resetTracking()
                return []
            }
        }

        guard let x = observation.x else {
            // No reading this frame (dropped/gated) — decay, never hard-reset.
            decayProgress(dt: dt)
            settlePhase(now: observation.timestamp)
            return []
        }

        buffer.removeAll { observation.timestamp - $0.t > tuning.waveWindow }
        buffer.append((observation.timestamp, x))

        let waveQualifies = reversalCount() >= tuning.waveMinReversals
            && amplitude() >= tuning.waveMinAmplitude
        let stationaryQualifies = updateStationary(x: x)

        if waveQualifies || stationaryQualifies {
            progress = min(tuning.waveHoldDuration, progress + dt)
        } else {
            decayProgress(dt: dt)
        }

        if progress >= tuning.waveHoldDuration {
            phase = .cooldown(until: observation.timestamp + tuning.waveCooldownDuration)
            resetTracking()
            return [.waved]
        }

        settlePhase(now: observation.timestamp)
        return []
    }

    private mutating func resetTracking() {
        progress = 0
        buffer.removeAll()
        stationaryAnchor = nil
    }

    private mutating func decayProgress(dt: TimeInterval) {
        guard progress > 0, dt > 0 else { return }
        let decayRate = tuning.waveHoldDuration / tuning.waveProgressDecay
        progress = max(0, progress - dt * decayRate)
    }

    private mutating func settlePhase(now: TimeInterval) {
        switch phase {
        case .idle:
            if progress > 0 { phase = .waving(since: now) }
        case .waving:
            if progress <= 0 {
                phase = .idle
                // A fully-decayed run is over — the next stationary attempt
                // gets a fresh anchor rather than one left over from a run
                // that already failed.
                stationaryAnchor = nil
            }
        case .cooldown:
            break
        }
    }

    /// True once `x` has stayed within `tuning.waveStationaryRadius` of the
    /// anchor captured at the start of this run. The anchor is deliberately
    /// **not** re-centered on every sample — that would make slow, steady
    /// drift indistinguishable from a genuine hold (each step alone is
    /// inside the radius of its predecessor). Instead, once `x` strays
    /// outside the original anchor's radius it stays disqualified — drift
    /// and carrying-speed motion both walk away from their start point and
    /// never come back, so they just decay out instead of re-qualifying.
    private mutating func updateStationary(x: Double) -> Bool {
        guard let anchor = stationaryAnchor else {
            stationaryAnchor = x
            return false
        }
        return abs(x - anchor) <= tuning.waveStationaryRadius
    }

    private func reversalCount() -> Int {
        guard buffer.count >= 3 else { return 0 }
        var count = 0
        var lastDirection = 0
        for i in 1..<buffer.count {
            let delta = buffer[i].x - buffer[i - 1].x
            let direction = delta > 1e-6 ? 1 : (delta < -1e-6 ? -1 : 0)
            guard direction != 0 else { continue }
            if lastDirection != 0, direction != lastDirection {
                count += 1
            }
            lastDirection = direction
        }
        return count
    }

    private func amplitude() -> Double {
        guard let mn = buffer.map(\.x).min(), let mx = buffer.map(\.x).max() else { return 0 }
        return mx - mn
    }
}
