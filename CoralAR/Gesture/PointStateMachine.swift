import Foundation

/// Opaque annotation id — Gesture/ RealityKit-free. See `SceneController.selectAnnotation(at:)`.
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
    /// Annotation under the index tip (hit-test only — NOT gated on `isPointing`; that gate is
    /// applied downstream via the smoothed majority vote, so a single misclassified frame doesn't
    /// blank the target outright).
    let target: AnnotationID?
    /// Raw per-frame `HandShapeClassifier.isPointing` result for this observation. Smoothed over
    /// a rolling window inside `PointStateMachine` before it's allowed to gate dwell.
    let isPointing: Bool
    /// Pinch active cancels dwell — point/carry never share a target. docs/GESTURES.md §2.9
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

    /// 0–1 dwell ring fill; held through grace like state. 1 when hovering.
    private(set) var dwellProgress: Double = 0

    /// Rolling window of raw `isPointing` readings, most recent last — majority-vote smoothing
    /// for "usable but wrong" shape-gate misreads. Separate mechanism from the per-state
    /// `lastSeenAt` grace period below, which tolerates genuinely unusable (nil/dropped) frames.
    /// Don't conflate the two: this one decides whether a *present* frame's classification is
    /// trustworthy; the grace period decides how long to wait through *absent* frames.
    private var pointingWindow: [Bool] = []

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func reset() {
        state = .idle
        dwellProgress = 0
        pointingWindow = []
    }

    @discardableResult
    mutating func process(_ observation: PointObservation) -> [PointEvent] {
        let now = observation.timestamp

        if observation.pinchActive {
            // Pinch cancels dwell; emit `.hoverEnded` only if already hovering.
            var events: [PointEvent] = []
            switch state {
            case .idle, .dwelling:
                break
            case .hovering(let target, _):
                events.append(.hoverEnded(target))
            }
            state = .idle
            dwellProgress = 0
            pointingWindow = []
            return events
        }

        // Majority-vote smoothing: a single misclassified frame (weak middle/ring/little
        // landmark) doesn't flip the vote as long as most of the recent window still agrees.
        pointingWindow.append(observation.isPointing)
        if pointingWindow.count > tuning.pointingWindowSize { pointingWindow.removeFirst() }
        let trueCount = pointingWindow.filter { $0 }.count
        let pointingSmoothed = trueCount * 2 > pointingWindow.count
        let effectiveTarget = pointingSmoothed ? observation.target : nil

        var events: [PointEvent] = []

        switch state {
        case .idle:
            if let target = effectiveTarget {
                state = .dwelling(target: target, since: now, lastSeenAt: now)
                dwellProgress = 0
            }

        case .dwelling(let target, let since, let lastSeenAt):
            if let seen = effectiveTarget {
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
                // Grace hold on dropped frame (same idea as PinchStateMachine.lastValidAt).
                break
            } else {
                state = .idle
                dwellProgress = 0
            }

        case .hovering(let target, let lastSeenAt):
            if let seen = effectiveTarget {
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
