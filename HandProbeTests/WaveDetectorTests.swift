import Foundation
import XCTest
@testable import HandProbe

/// Wave / stationary-hold — explicit clock, frame=1/15 like ManipulationTrackerSettlingTests.
final class WaveDetectorTests: XCTestCase {
    private let frame: TimeInterval = 1.0 / 15.0

    private func makeDetector() -> WaveDetector {
        WaveDetector(tuning: .default)
    }

    /// Oscillating wrist x: enough reversals + amplitude inside waveWindow ⇒ waving.
    private func waveX(at t: TimeInterval, center: Double = 0.5, amplitude: Double = 0.08, period: TimeInterval = 0.25) -> Double {
        center + amplitude * sin(2 * .pi * t / period)
    }

    /// Feed seconds of wave from startTime; returns events fired + end clock.
    @discardableResult
    private func feedWave(
        _ detector: inout WaveDetector,
        seconds: TimeInterval,
        startTime: TimeInterval,
        phaseOffset: TimeInterval = 0
    ) -> (events: [WaveEvent], endTime: TimeInterval) {
        var events: [WaveEvent] = []
        var t = startTime
        let end = startTime + seconds
        while t < end {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t - phaseOffset)))
            t += frame
        }
        return (events, t)
    }

    func testTwoSecondWaveFiresOnce() {
        var detector = makeDetector()
        let (events, _) = feedWave(&detector, seconds: 3.0, startTime: 0)
        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "a sustained 3s wave should fire exactly once")
    }

    func testOneSecondWaveDoesNotFire() {
        var detector = makeDetector()
        let (events, _) = feedWave(&detector, seconds: 1.0, startTime: 0)
        XCTAssertTrue(events.isEmpty, "1s of wave motion is under the 2.0s hold duration")
    }

    /// Brief nil-x gap decays progress, must not hard-reset — GESTURES.md §2.10.
    func testGapOfTwoFramesStillFires() {
        var detector = makeDetector()
        var t: TimeInterval = 0
        var events: [WaveEvent] = []

        // ~1.9s of wave motion.
        let preGapEnd = t + 1.9
        while t < preGapEnd {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t)))
            t += frame
        }

        // 2-frame nil gap.
        for _ in 0..<2 {
            events += detector.process(WaveObservation(timestamp: t, x: nil))
            t += frame
        }

        // Resume 1.0s: hard-reset couldn't hit 2.0s hold; decay only lost ~0.13s gap.
        let postGapEnd = t + 1.0
        while t < postGapEnd {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t)))
            t += frame
        }

        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "a short gap must decay progress, not hard-reset it")
    }

    /// Slow monotonic drift: no reversals, leaves stationary anchor — must never fire.
    func testSlowDriftNeverFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 6.0
        let driftRate = 0.02 // per second — well beyond stationaryRadius within a fraction of a second
        while t < end {
            let x = 0.5 + driftRate * t
            events += detector.process(WaveObservation(timestamp: t, x: x))
            t += frame
        }
        XCTAssertTrue(events.isEmpty, "monotonic drift is neither a wave nor a stationary hold")
    }

    /// Fast lateral carry/drag: no reversals, past stationary radius — never wave/hold.
    func testCarryingSpeedTranslationNeverFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 3.0
        while t < end {
            let x = 0.2 + 0.15 * t // fast, steady, one direction
            events += detector.process(WaveObservation(timestamp: t, x: min(x, 1.0)))
            t += frame
        }
        XCTAssertTrue(events.isEmpty, "fast one-directional motion must not trigger the wave path")
    }

    /// Stationary-hold fallback: still (jitter < radius) for hold duration → .waved.
    func testStationaryHoldFallbackFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 2.5
        var toggle = false
        while t < end {
            // Tiny jitter, well inside waveStationaryRadius (0.02).
            toggle.toggle()
            let x = 0.5 + (toggle ? 0.003 : -0.003)
            events += detector.process(WaveObservation(timestamp: t, x: x))
            t += frame
        }
        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "holding still for 2s should fire via the fallback")
    }

    /// Cooldown suppresses an immediate second fire right after the first.
    func testCooldownSuppressesImmediateSecondFire() {
        var detector = makeDetector()
        let (firstRun, endTime) = feedWave(&detector, seconds: 3.0, startTime: 0)
        XCTAssertEqual(firstRun.filter { $0 == .waved }.count, 1)

        // Immediately keep waving right after the first fire — still inside cooldown.
        let (secondRun, _) = feedWave(&detector, seconds: 1.0, startTime: endTime)
        XCTAssertTrue(secondRun.filter { $0 == .waved }.isEmpty, "cooldown should block an immediate re-fire")
    }

    func testResetClearsProgress() {
        var detector = makeDetector()
        _ = feedWave(&detector, seconds: 1.0, startTime: 0)
        XCTAssertGreaterThan(detector.progress, 0)
        detector.reset()
        XCTAssertEqual(detector.progress, 0)
    }
}
