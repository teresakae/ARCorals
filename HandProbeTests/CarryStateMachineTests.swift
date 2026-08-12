import Foundation
import XCTest
@testable import HandProbe

/// Carry toggle-latch over synthetic PinchGestureEvent timestamps — see GESTURES.md §2.8.
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
        // Over tuning.carryToggleMaxDuration (0.7s) — a grab-and-drag, not a toggle.
        let events = machine.process(CarryObservation(timestamp: 0.8, pinchEvent: .ended(ratio: 3.0), target: nil))

        XCTAssertEqual(events, [])
        XCTAssertNil(machine.carried)
    }

    func testSecondShortCyclePutsDown() {
        var machine = makeMachine()
        _ = machine.process(CarryObservation(timestamp: 0.0, pinchEvent: .began(ratio: 1.0), target: targetA))
        _ = machine.process(CarryObservation(timestamp: 0.2, pinchEvent: .ended(ratio: 3.0), target: nil))
        XCTAssertEqual(machine.carried, targetA)

        // Put-down always targets the carried entity, ignoring this toggle's hit-test target.
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

        // Cancelled pinch must clear in-flight start — next pinch is a fresh toggle candidate.
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
        // Regression: second pickup after put-down must not inherit residue from the first cycle.
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

    /// Re-grab: never-placed→Carry; after putDown→rotate if allowRotate (`.carry`). GESTURES.md §1.
    func testRegrabRoutesToRotateAfterPutDown() {
        XCTAssertEqual(
            routeCarryPinch(target: targetA, previouslyPlaced: [], isCarrying: false, allowRotate: true),
            .carry
        )
        XCTAssertEqual(
            routeCarryPinch(target: targetA, previouslyPlaced: [targetA], isCarrying: false, allowRotate: true),
            .rotate
        )
        // Put-down toggle must not be stolen while still carrying.
        XCTAssertEqual(
            routeCarryPinch(target: targetA, previouslyPlaced: [targetA], isCarrying: true, allowRotate: true),
            .carry
        )
        XCTAssertNil(routeCarryPinch(target: nil, previouslyPlaced: [targetA], isCarrying: false, allowRotate: true))
    }

    /// `.sim` sets allowRotate:false — re-grab stays `.carry`, never `.rotate`. GESTURES.md §1.
    func testRegrabStaysCarryWhenRotateDisallowed() {
        XCTAssertEqual(
            routeCarryPinch(target: targetA, previouslyPlaced: [targetA], isCarrying: false, allowRotate: false),
            .carry
        )
        // Still-carrying case is unaffected by allowRotate.
        XCTAssertEqual(
            routeCarryPinch(target: targetA, previouslyPlaced: [targetA], isCarrying: true, allowRotate: false),
            .carry
        )
    }
}
