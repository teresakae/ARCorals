import Foundation

/// Identity of a placed entity, opaque to the Gesture layer. Callers pass
/// `ObjectIdentifier(modelEntity)` — same handle Prompt B's AnnotationID map
/// is built around — so this layer never needs to import RealityKit.
typealias EntityID = ObjectIdentifier

/// Carry (pinch-toggle pick up / place) lifecycle events.
enum CarryEvent: Equatable, Sendable {
    case pickedUp(EntityID)
    case putDown(EntityID)
}

/// One sample from the carry-toggle stream. Carry does not re-derive pinch
/// detection — it reacts to `PinchStateMachine`'s own event output.
struct CarryObservation: Equatable, Sendable {
    let timestamp: TimeInterval
    let pinchEvent: PinchGestureEvent
    /// Which placed entity, if any, the pinch point hit-tested onto this
    /// frame. Only consulted on `.began` while `empty` — a toggle that
    /// starts while already carrying always targets the carried entity,
    /// wherever the second pinch lands (see `process`).
    let target: EntityID?
}

/// Carry toggle-latch lifecycle. Feed observations; collect events.
///
/// `empty` + a short pinch (began→ended under `tuning.carryToggleMaxDuration`)
/// that began on a target → `carrying(id)`, emits `.pickedUp(id)`. A pinch
/// over that duration, or one that ends in `.cancelled`, is a grab (today's
/// existing Adjust/Move flow) rather than a toggle — no event, stays put.
/// `carrying(id)` + another short pinch (any target) → `empty`, `.putDown(id)`.
struct CarryStateMachine: Sendable {
    var tuning: GestureTuning

    /// The only piece of carry state a caller needs. `nil` = nothing carried.
    private(set) var carried: EntityID?

    private var pinchStart: TimeInterval?
    /// Snapshot of what the in-flight pinch would toggle, taken at `.began`:
    /// the currently carried entity if there is one, else whatever the pinch
    /// point hit. Reading `carried`/`target` again at `.ended` would be wrong
    /// the instant a pickup and a put-down could ever straddle two different
    /// hit-tests — this pins the toggle to the entity the pinch actually
    /// started on.
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
            // A long hold-and-drag pinch that gets cancelled (tracking loss,
            // grace period expiry) is not a toggle either — same as running
            // out the clock, just via a different exit. No state change.
            pinchStart = nil
            pinchTarget = nil
            return []

        case .possible, .changed, .failed:
            return []
        }
    }
}
