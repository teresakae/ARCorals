import Foundation

/// Identifies one annotation hotspot. Opaque wrapper so `Gesture/` stays free
/// of RealityKit — `SceneController` maps its own entity identities onto this
/// (see `SceneController.selectAnnotation(at:)`).
struct AnnotationID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Point-and-dwell lifecycle events.
enum PointEvent: Equatable, Sendable {
    case hoverBegan(AnnotationID)
    case hoverEnded(AnnotationID)
}

/// One sample from the point-target stream.
struct PointObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    /// Annotation the index fingertip is currently over. Nil if not pointing,
    /// pointing at nothing, or gated out by confidence.
    let target: AnnotationID?
    /// True while a pinch is active (began/changed). A pinch beginning
    /// cancels any in-progress dwell outright — point and carry never run
    /// together on the same target.
    let pinchActive: Bool
}

/// Point-and-dwell lifecycle. Feed observations; collect events.
struct PointStateMachine: Sendable {
    var tuning: GestureTuning

    private enum State: Equatable {
        case idle
        case dwelling(target: AnnotationID, since: TimeInterval, lastSeenAt: TimeInterval)
        case hovering(target: AnnotationID, lastSeenAt: TimeInterval)
    }

    private var state: State = .idle

    /// 0–1 fill for a dwell-in-progress ring UI affordance. 1 once hovering,
    /// 0 when idle. Held steady (not recomputed) through a dropped-frame
    /// grace window, same as the state itself.
    private(set) var dwellProgress: Double = 0

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func reset() {
        state = .idle
        dwellProgress = 0
    }

    @discardableResult
    mutating func process(_ observation: PointObservation) -> [PointEvent] {
        let now = observation.timestamp

        if observation.pinchActive {
            // Point and carry never run together on the same target — a
            // pinch beginning cancels any in-progress dwell outright, with
            // no event unless a hover popup was already showing.
            var events: [PointEvent] = []
            switch state {
            case .idle, .dwelling:
                break
            case .hovering(let target, _):
                events.append(.hoverEnded(target))
            }
            state = .idle
            dwellProgress = 0
            return events
        }

        var events: [PointEvent] = []

        switch state {
        case .idle:
            if let target = observation.target {
                state = .dwelling(target: target, since: now, lastSeenAt: now)
                dwellProgress = 0
            }

        case .dwelling(let target, let since, let lastSeenAt):
            if let seen = observation.target {
                if seen == target {
                    let elapsed = now - since
                    if elapsed >= tuning.pointDwellDuration {
                        state = .hovering(target: target, lastSeenAt: now)
                        dwellProgress = 1
                        events.append(.hoverBegan(target))
                    } else {
                        state = .dwelling(target: target, since: since, lastSeenAt: now)
                        dwellProgress = min(1, elapsed / tuning.pointDwellDuration)
                    }
                } else {
                    // Switched target — restart the dwell clock on the new one.
                    state = .dwelling(target: seen, since: now, lastSeenAt: now)
                    dwellProgress = 0
                }
            } else if now - lastSeenAt <= tuning.gracePeriod {
                // Dropped frame within grace — hold the dwell in progress,
                // same pattern as PinchStateMachine's lastValidAt.
                break
            } else {
                state = .idle
                dwellProgress = 0
            }

        case .hovering(let target, let lastSeenAt):
            if let seen = observation.target {
                if seen == target {
                    state = .hovering(target: target, lastSeenAt: now)
                } else {
                    events.append(.hoverEnded(target))
                    state = .dwelling(target: seen, since: now, lastSeenAt: now)
                    dwellProgress = 0
                }
            } else if now - lastSeenAt <= tuning.gracePeriod {
                break
            } else {
                events.append(.hoverEnded(target))
                state = .idle
                dwellProgress = 0
            }
        }

        return events
    }
}
