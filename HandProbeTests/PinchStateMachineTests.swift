import Foundation
import XCTest
@testable import HandProbe

final class PinchStateMachineTests: XCTestCase {
    private let dt: TimeInterval = 0.066
    private var tuning = GestureTuning.default

    private func machine() -> PinchStateMachine {
        PinchStateMachine(tuning: tuning)
    }

    private func obs(
        t: TimeInterval,
        ratio: Double?,
        confidence: Float? = 0.9
    ) -> PinchObservation {
        PinchObservation(timestamp: t, pinchRatio: ratio, confidence: confidence)
    }

    /// Feeds ratios on a continuous clock starting at `start`. Returns events and next timestamp.
    private func feed(
        _ sm: inout PinchStateMachine,
        ratios: [Double?],
        start: TimeInterval,
        confidence: Float? = 0.9
    ) -> (events: [PinchGestureEvent], nextTime: TimeInterval) {
        var events: [PinchGestureEvent] = []
        var t = start
        for r in ratios {
            events += sm.process(obs(t: t, ratio: r, confidence: confidence))
            t += dt
        }
        return (events, t)
    }

    private func names(_ events: [PinchGestureEvent]) -> [String] {
        events.map(\.name)
    }

    private func armPinch(_ sm: inout PinchStateMachine, start: TimeInterval = 0) -> TimeInterval {
        let (_, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: start)
        return t
    }

    // MARK: - Clean pinch

    func testCleanPinch() {
        var sm = machine()
        var t: TimeInterval = 0
        var events: [PinchGestureEvent]

        (events, t) = feed(&sm, ratios: [10, 10, 10], start: t)
        XCTAssertEqual(names(events), [])

        (events, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: t)
        XCTAssertEqual(events.first?.name, "Began")

        (events, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: t)
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })

        (events, t) = feed(&sm, ratios: [12, 12, 12], start: t)
        XCTAssertTrue(names(events).contains("Ended"))
        XCTAssertTrue(names(events).contains("Possible"))
    }

    // MARK: - Chatter in noise band

    func testChatterInNoiseBandDoesNotBegin() {
        var sm = machine()
        // Noise band around shipping pinchThreshold 1.98 ± hysteresisBand/2 → [1.48, 2.48].
        let chatter: [Double?] = (0..<30).map { i in i % 2 == 0 ? 1.7 : 2.2 }
        let (events, _) = feed(&sm, ratios: chatter, start: 0)
        XCTAssertFalse(names(events).contains("Began"), "band chatter must not arm a pinch")
    }

    func testChatterDoesNotEndActiveDrag() {
        var sm = machine()
        var t = armPinch(&sm)
        let band: [Double?] = (0..<20).map { i in i % 2 == 0 ? 1.7 : 2.3 }
        let (events, _) = feed(&sm, ratios: band, start: t)
        XCTAssertFalse(names(events).contains("Ended"))
        XCTAssertFalse(names(events).contains("Cancelled"))
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })
    }

    // MARK: - Grace: 2 dropped frames

    func testDragSurvivesTwoDroppedFrames() {
        var sm = machine()
        var t = armPinch(&sm)
        // 2 drops @ 66ms = 132ms < 200ms grace
        var events: [PinchGestureEvent]
        (events, t) = feed(&sm, ratios: [nil, nil], start: t)
        XCTAssertFalse(names(events).contains("Cancelled"))
        (events, t) = feed(&sm, ratios: [0.5, 0.5], start: t)
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })
    }

    // MARK: - Grace: 10 dropped frames

    func testDragCancelsAfterTenDroppedFrames() {
        var sm = machine()
        let t = armPinch(&sm)
        let (events, _) = feed(&sm, ratios: Array(repeating: nil, count: 10), start: t)
        XCTAssertTrue(names(events).contains("Cancelled"))
        XCTAssertTrue(names(events).contains("Possible"))
    }

    // MARK: - Confidence collapse

    func testConfidenceCollapseTreatedAsDrop() {
        var sm = machine()
        var t = armPinch(&sm)
        var events: [PinchGestureEvent] = []
        for _ in 0..<10 {
            events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
            t += dt
        }
        XCTAssertTrue(names(events).contains("Cancelled"))
    }

    func testBriefConfidenceCollapseDoesNotCancel() {
        var sm = machine()
        var t = armPinch(&sm)
        var events: [PinchGestureEvent] = []
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
        t += dt
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
        t += dt
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.9))
        XCTAssertFalse(names(events).contains("Cancelled"))
        XCTAssertTrue(names(events).contains("Changed"))
    }
}
