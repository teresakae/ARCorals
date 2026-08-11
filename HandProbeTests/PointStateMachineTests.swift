import Foundation
import XCTest
@testable import HandProbe

final class PointStateMachineTests: XCTestCase {
    private let dt: TimeInterval = 0.066
    private let tuning = GestureTuning.default
    private let annotationA = AnnotationID("A")

    private func machine() -> PointStateMachine {
        PointStateMachine(tuning: tuning)
    }

    private func obs(t: TimeInterval, target: AnnotationID?, pinchActive: Bool = false) -> PointObservation {
        PointObservation(timestamp: t, target: target, pinchActive: pinchActive)
    }

    /// Feeds targets on a continuous clock starting at `start`. Returns events and next timestamp.
    private func feed(
        _ sm: inout PointStateMachine,
        targets: [AnnotationID?],
        start: TimeInterval,
        pinchActive: Bool = false
    ) -> (events: [PointEvent], nextTime: TimeInterval) {
        var events: [PointEvent] = []
        var t = start
        for target in targets {
            events += sm.process(obs(t: t, target: target, pinchActive: pinchActive))
            t += dt
        }
        return (events, t)
    }

    // MARK: - Dwell completes

    func testDwellCompletesFiresHoverBegan() {
        var sm = machine()
        // 0.4s dwell / 66ms frames needs 7 frames to cross the threshold; 8 is comfortably past it.
        let (events, _) = feed(&sm, targets: Array(repeating: annotationA, count: 8), start: 0)
        XCTAssertEqual(events, [.hoverBegan(annotationA)])
    }

    // MARK: - Dwell abandoned early

    func testDwellAbandonedEarlyFiresNoEvent() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        // Well past the grace period — the dwell fully lapses before ever completing.
        (events, t) = feed(&sm, targets: Array(repeating: nil, count: 5), start: t)
        _ = t
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Grace: 2 dropped frames

    func testTargetLostTwoFramesSurvivesDwell() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        // 2 drops @ 66ms = 132ms < 200ms grace
        (events, t) = feed(&sm, targets: [nil, nil], start: t)
        XCTAssertTrue(events.isEmpty)
        (events, t) = feed(&sm, targets: Array(repeating: annotationA, count: 6), start: t)
        _ = t
        XCTAssertEqual(events, [.hoverBegan(annotationA)])
    }

    // MARK: - Grace: 10 dropped frames

    func testTargetLostTenFramesFiresHoverEnded() {
        var sm = machine()
        let (_, t) = feed(&sm, targets: Array(repeating: annotationA, count: 8), start: 0)
        let (events, _) = feed(&sm, targets: Array(repeating: nil, count: 10), start: t)
        XCTAssertTrue(events.contains(.hoverEnded(annotationA)))
    }

    // MARK: - Pinch cancels an in-progress dwell

    func testPinchBeginningMidDwellCancelsWithNoHoverEvent() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        (events, _) = feed(&sm, targets: [nil], start: t, pinchActive: true)
        XCTAssertTrue(events.isEmpty)
    }
}
