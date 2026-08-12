import Foundation

/// One sample from the (ratio, confidence) stream.
struct PinchObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    let pinchRatio: Double?
    let confidence: Float?
}

enum PinchGestureEvent: Equatable, Sendable {
    case possible
    case began(ratio: Double)
    case changed(ratio: Double)
    case ended(ratio: Double)
    case cancelled
    case failed

    var name: String {
        switch self {
        case .possible: return "Possible"
        case .began: return "Began"
        case .changed: return "Changed"
        case .ended: return "Ended"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }
}

/// Standalone pinch lifecycle. Feed observations; collect events.
struct PinchStateMachine: Sendable {
    private(set) var tuning: GestureTuning
    private(set) var phase: PinchGestureEvent = .possible
    /// When set (scale-mode lock), consulted instead of `tuning.pinchExitThreshold`.
    var exitThresholdOverride: Double?

    /// 0–1 fill during the pendingBegan hysteresis window; 1 once committed (active/pendingEnd), 0 when idle.
    /// Same pattern as `PointStateMachine.dwellProgress` — user-facing pinch-commit affordance.
    private(set) var pendingProgress: Double = 0

    private enum Internal: Equatable {
        case idle
        case pendingBegan(start: TimeInterval, lastValidAt: TimeInterval)
        case active(beganAt: TimeInterval, lastValidAt: TimeInterval)
        case pendingEnd(start: TimeInterval, beganAt: TimeInterval, lastValidAt: TimeInterval)
    }

    private var internalState: Internal = .idle

    private var exitThreshold: Double {
        exitThresholdOverride ?? tuning.pinchExitThreshold
    }

    init(tuning: GestureTuning = GestureTuning()) {
        self.tuning = tuning
    }

    mutating func reset() {
        internalState = .idle
        phase = .possible
        exitThresholdOverride = nil
        pendingProgress = 0
    }

    @discardableResult
    mutating func process(_ observation: PinchObservation) -> [PinchGestureEvent] {
        let usable = Self.usableRatio(observation, gate: tuning.confidenceGate)
        var events: [PinchGestureEvent] = []

        switch internalState {
        case .idle:
            if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                internalState = .pendingBegan(start: observation.timestamp, lastValidAt: observation.timestamp)
            }

        case .pendingBegan(let start, let lastValidAt):
            if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                if observation.timestamp - start >= tuning.hysteresisDuration {
                    internalState = .active(beganAt: observation.timestamp, lastValidAt: observation.timestamp)
                    let began = PinchGestureEvent.began(ratio: ratio)
                    phase = began
                    events.append(began)
                } else {
                    internalState = .pendingBegan(start: start, lastValidAt: observation.timestamp)
                }
            } else if usable == nil {
                // Unusable (dropped/low-confidence) frame — same grace-period tolerance `.active` gets,
                // not a real release signal. A genuine valid ratio back above threshold (below) still
                // resets immediately: that's real motion, not sensor dropout.
                if observation.timestamp - lastValidAt > tuning.gracePeriod {
                    internalState = .idle
                }
            } else {
                internalState = .idle
            }

        case .active(let beganAt, let lastValidAt):
            if let ratio = usable {
                if ratio > exitThreshold {
                    internalState = .pendingEnd(
                        start: observation.timestamp,
                        beganAt: beganAt,
                        lastValidAt: observation.timestamp
                    )
                } else {
                    internalState = .active(beganAt: beganAt, lastValidAt: observation.timestamp)
                    let changed = PinchGestureEvent.changed(ratio: ratio)
                    phase = changed
                    events.append(changed)
                }
            } else if observation.timestamp - lastValidAt > tuning.gracePeriod {
                internalState = .idle
                events.append(.cancelled)
                events.append(.possible)
                phase = .possible
            }

        case .pendingEnd(let start, let beganAt, let lastValidAt):
            if usable == nil {
                if observation.timestamp - lastValidAt > tuning.gracePeriod {
                    internalState = .idle
                    events.append(.cancelled)
                    events.append(.possible)
                    phase = .possible
                } else {
                    internalState = .pendingEnd(start: start, beganAt: beganAt, lastValidAt: lastValidAt)
                }
            } else if let ratio = usable, ratio > exitThreshold {
                if observation.timestamp - start >= tuning.hysteresisDuration {
                    internalState = .idle
                    let ended = PinchGestureEvent.ended(ratio: ratio)
                    phase = ended
                    events.append(ended)
                    events.append(.possible)
                    phase = .possible
                }
            } else if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                internalState = .active(beganAt: beganAt, lastValidAt: observation.timestamp)
                let changed = PinchGestureEvent.changed(ratio: ratio)
                phase = changed
                events.append(changed)
            } else if let ratio = usable {
                internalState = .pendingEnd(
                    start: start,
                    beganAt: beganAt,
                    lastValidAt: observation.timestamp
                )
                let changed = PinchGestureEvent.changed(ratio: ratio)
                phase = changed
                events.append(changed)
            }
        }

        switch internalState {
        case .idle:
            pendingProgress = 0
        case .pendingBegan(let start, _):
            pendingProgress = min(1, max(0, (observation.timestamp - start) / tuning.hysteresisDuration))
        case .active, .pendingEnd:
            pendingProgress = 1
        }

        return events
    }

    private static func usableRatio(_ observation: PinchObservation, gate: Float) -> Double? {
        guard let ratio = observation.pinchRatio else { return nil }
        if let confidence = observation.confidence, confidence < gate {
            return nil
        }
        return ratio
    }
}
