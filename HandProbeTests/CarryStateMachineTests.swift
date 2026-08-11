import Foundation
import XCTest
@testable import HandProbe

/// Carry is a toggle-latch over `PinchStateMachine`'s own event stream — these
/// feed it synthetic `PinchGestureEvent` sequences with hand-picked
/// timestamps, `MoveTriggerTests`' pure-timestamp style, rather than
/// re-deriving pinch detection from raw ratios (already covered by
/// `PinchStateMachineTests`).
final class CarryStateMachineTests: XCTestCase {
    private let targetA = EntityID(NSObject())
    private let targetB = EntityID(NSObject())

    private func makeMachine() -> CarryStateMachine {
        CarryStateMachine(tuning: .default)
    }

    func testShortCycleOnTargetPicksUp() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        let events = machine.process(CarryObservation(timestamp: 0.2, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [.pickedUp(targetA)])
        XCTAssertEqual(machine.carried, targetA)
    }

    func testLongCycleDoesNothing() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        // Over tuning.carryToggleMaxDuration (0.5s) — a grab-and-drag, not a toggle.
        let events = machine.process(CarryObservation(timestamp: 0.8, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [])
        XCTAssertNil(machine.carried)
    }

    func testSecondShortCyclePutsDown() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        _ = machine.process(CarryObservation(timestamp: 0.2, pinchEvent: .ended(ratio: 3.0), target: nil))
        XCTAssertEqual(machine.carried, targetA)

        // Second toggle's own hit-test target (targetB, or none) doesn't
        // matter — a put-down always targets whatever is currently carried.
        _ = machine.process(CarryObservation(timestamp: 1.0, pinchEvent: .began(ratio: 1.0), target: targetB))
        let events = machine.process(CarryObservation(timestamp: 1.2, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [.putDown(targetA)])
        XCTAssertNil(machine.carried)
    }

    func testCancelledMidPinchNoStateChange() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        let events = machine.process(CarryObservation(timestamp: 0.1, pinchEvent: .cancelled, target: nil))

        XCTAssertEqual(events, [])
        XCTAssertNil(machine.carried)

        // The cancelled pinch must not leave a stale in-flight start time
        // behind either — the next pinch is a fresh toggle candidate.
        _ = machine.process(CarryObservation(timestamp: 5.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        let nextEvents = machine.process(CarryObservation(timestamp: 5.2, pinchEvent: .ended(ratio: 3.0), target: nil))
        XCTAssertEqual(nextEvents, [.pickedUp(targetA)])
    }

    func testPinchOnEmptySpaceDoesNothing() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: nil))
        let events = machine.process(CarryObservation(timestamp: 0.2, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [])
        XCTAssertNil(machine.carried)
    }

    func testSecondObjectDoesNotInheritFirstsState() {
        // GESTURE_LOG.md guard: picking up a second object after putting the
        // first one down must not carry any residue from the first cycle.
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        _ = machine.process(CarryObservation(timestamp: 0.2, pinchEvent: .ended(ratio: 3.0), target: nil))
        _ = machine.process(CarryObservation(timestamp: 1.0, pinchEvent: .began(ratio: 1.0), target: nil))
        _ = machine.process(CarryObservation(timestamp: 1.2, pinchEvent: .ended(ratio: 3.0), target: nil))
        XCTAssertNil(machine.carried)

        _ = machine.process(CarryObservation(timestamp: 2.0, pinchEvent: .began(ratio: 1.0), target: targetB))
        let events = machine.process(CarryObservation(timestamp: 2.2, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [.pickedUp(targetB)])
        XCTAssertEqual(machine.carried, targetB)
    }
}
