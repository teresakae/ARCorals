import Foundation

/// One sample from the (ratio, confidence) stream. No camera / Vision types.
struct PinchObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    /// `ratios.palmWidth`. `nil` = dropped frame / no hand / gated out.
    let pinchRatio: Double?
    /// Observation confidence; `nil` or below gate treated as a drop.
    let confidence: Float?
}

/// Lifecycle events. Matches TESTING.md Phase 2 event column.
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

/// Standalone pinch lifecycle. No camera/UI. Feed observations; collect events.
struct PinchStateMachine: Sendable {
    private(set) var tuning: GestureTuning
    private(set) var phase: PinchGestureEvent = .possible

    private enum Internal: Equatable {
        case idle
        case pendingBegan(start: TimeInterval)
        case active(beganAt: TimeInterval, lastValidAt: TimeInterval)
        case pendingEnd(start: TimeInterval, beganAt: TimeInterval, lastValidAt: TimeInterval)
    }

    private var internalState: Internal = .idle

    init(tuning: GestureTuning = GestureTuning()) {
        self.tuning = tuning
    }

    mutating func reset() {
        internalState = .idle
        phase = .possible
    }

    /// Process one observation. Returns events emitted this step (0…n).
    @discardableResult
    mutating func process(_ observation: PinchObservation) -> [PinchGestureEvent] {
        let usable = Self.usableRatio(observation, gate: tuning.confidenceGate)
        var events: [PinchGestureEvent] = []

        switch internalState {
        case .idle:
            if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                internalState = .pendingBegan(start: observation.timestamp)
            }

        case .pendingBegan(let start):
            if usable == nil {
                // Drop during arming — abort candidate (not yet a drag).
                internalState = .idle
            } else if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                if observation.timestamp - start >= tuning.hysteresisDuration {
                    internalState = .active(beganAt: observation.timestamp, lastValidAt: observation.timestamp)
                    let began = PinchGestureEvent.began(ratio: ratio)
                    phase = began
                    events.append(began)
                }
            } else {
                // Left the enter side (open or in-band chatter).
                internalState = .idle
            }

        case .active(let beganAt, let lastValidAt):
            if let ratio = usable {
                if ratio > tuning.pinchExitThreshold {
                    internalState = .pendingEnd(
                        start: observation.timestamp,
                        beganAt: beganAt,
                        lastValidAt: observation.timestamp
                    )
                } else {
                    // Still pinched or in hysteresis band — hold the drag.
                    internalState = .active(beganAt: beganAt, lastValidAt: observation.timestamp)
                    let changed = PinchGestureEvent.changed(ratio: ratio)
                    phase = changed
                    events.append(changed)
                }
            } else if observation.timestamp - lastValidAt > tuning.gracePeriod {
                internalState = .idle
                let cancelled = PinchGestureEvent.cancelled
                phase = cancelled
                events.append(cancelled)
                events.append(.possible)
                phase = .possible
            }
            // else: within grace — keep active, no event

        case .pendingEnd(let start, let beganAt, let lastValidAt):
            if usable == nil {
                // Drop while ending: treat as tracking loss from last valid.
                if observation.timestamp - lastValidAt > tuning.gracePeriod {
                    internalState = .idle
                    events.append(.cancelled)
                    events.append(.possible)
                    phase = .possible
                } else {
                    internalState = .pendingEnd(start: start, beganAt: beganAt, lastValidAt: lastValidAt)
                }
            } else if let ratio = usable, ratio > tuning.pinchExitThreshold {
                if observation.timestamp - start >= tuning.hysteresisDuration {
                    internalState = .idle
                    let ended = PinchGestureEvent.ended(ratio: ratio)
                    phase = ended
                    events.append(ended)
                    events.append(.possible)
                    phase = .possible
                }
            } else if let ratio = usable, ratio < tuning.pinchEnterThreshold {
                // Re-pinched — cancel the end candidate, stay active.
                internalState = .active(beganAt: beganAt, lastValidAt: observation.timestamp)
                let changed = PinchGestureEvent.changed(ratio: ratio)
                phase = changed
                events.append(changed)
            } else if let ratio = usable {
                // In-band during pending end — keep waiting, refresh validity.
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

        return events
    }

    private static func usableRatio(_ observation: PinchObservation, gate: Float) -> Double? {
        guard let ratio = observation.pinchRatio else { return nil }
        if let confidence = observation.confidence, confidence < gate {
            return nil
        }
        // Missing confidence with a ratio still counts (synthetic tests may omit it).
        return ratio
    }
}
