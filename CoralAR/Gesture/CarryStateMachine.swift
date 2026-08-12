import Foundation

/// Placed-entity id (`ObjectIdentifier`); Gesture/ stays RealityKit-free. docs/ARCHITECTURE.md
typealias EntityID = ObjectIdentifier

/// Carry (pinch-toggle pick up / place) lifecycle events.
enum CarryEvent: Equatable, Sendable {
    case pickedUp(EntityID)
    case putDown(EntityID)
}

/// Carry vs re-grab-rotate. Rotate only when `allowRotate` (`.carry`/O1). docs/GESTURES.md §1
enum CarryPinchRoute: Equatable, Sendable {
    case carry
    case rotate
}

/// Re-grab → rotate iff put-down once + `allowRotate`; else carry. docs/ARCHITECTURE.md
func routeCarryPinch(
    target: EntityID?,
    previouslyPlaced: Set<EntityID>,
    isCarrying: Bool,
    allowRotate: Bool
) -> CarryPinchRoute? {
    if isCarrying { return .carry }
    guard let target else { return nil }
    if previouslyPlaced.contains(target) && allowRotate { return .rotate }
    return .carry
}

/// Carry input: reacts to `PinchStateMachine` events; does not re-detect pinch.
struct CarryObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    let pinchEvent: PinchGestureEvent
    /// Hit-tested entity; used only on `.began` while empty — put-down ignores landing target.
    let target: EntityID?
}

/// Short pinch (<`carryToggleMaxDuration`) toggles pick-up/put-down. docs/GESTURES.md §2.8
struct CarryStateMachine: Sendable {
    var tuning: GestureTuning

    /// The only piece of carry state a caller needs. `nil` = nothing carried.
    private(set) var carried: EntityID?

    private var pinchStart: TimeInterval?
    /// ⚠️ Toggle target latched at `.began` — never re-read `carried`/`target` at `.ended`.
    private var pinchTarget: EntityID?

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func reset() {
        carried = nil
        pinchStart = nil
        pinchTarget = nil
    }

    @discardableResult
    mutating func process(_ observation: CarryObservation) -> [CarryEvent] {
        switch observation.pinchEvent {
        case .began:
            pinchStart = observation.timestamp
            pinchTarget = carried ?? observation.target
            return []

        case .ended:
            defer {
                pinchStart = nil
                pinchTarget = nil
            }
            guard let start = pinchStart, let target = pinchTarget,
                  observation.timestamp - start < tuning.carryToggleMaxDuration else {
                return []
            }
            if carried == nil {
                carried = target
                return [.pickedUp(target)]
            } else {
                carried = nil
                return [.putDown(target)]
            }

        case .cancelled:
            // Cancelled ≠ toggle; clear in-flight pinch, no state change.
            pinchStart = nil
            pinchTarget = nil
            return []

        case .possible, .changed, .failed:
            return []
        }
    }
}
