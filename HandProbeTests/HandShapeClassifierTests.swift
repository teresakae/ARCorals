import Foundation
import Vision
import XCTest
@testable import HandProbe

final class HandShapeClassifierTests: XCTestCase {
    /// These fixtures lay palmWidth flat along x and every finger along y, so the production
    /// default (`PinchRatioCalculator.defaultDyAspectCorrection`, 1440/1920 = 0.75) would scale
    /// every finger length but not the palm — the ratios would no longer be the numbers written
    /// in each case. The de-skew is correct on real landmarks; here it only obscures the
    /// threshold under test, so these cases pin it to 1.0 and vary the ratio directly.
    private static let noAspectCorrection = 1.0

    /// palmWidth fixed at 1.0 so tip/MCP ratios match GestureTuning constants directly.
    private func makeJoints(
        pinchDist: Double,
        fingerExtendedRatio: Double
    ) -> [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample] {
        func j(_ name: HumanHandPoseObservation.JointName, _ x: CGFloat, _ y: CGFloat) -> LandmarkFrame.JointSample {
            LandmarkFrame.JointSample(name: name, x: x, y: y, confidence: 1.0)
        }

        var joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample] = [
            .indexMCP: j(.indexMCP, 0, 0),
            .littleMCP: j(.littleMCP, 1, 0),
            .thumbTip: j(.thumbTip, 0, 0),
            .indexTip: j(.indexTip, CGFloat(pinchDist), 0),
            .middleMCP: j(.middleMCP, 0.5, 0),
            .ringMCP: j(.ringMCP, 0.75, 0),
        ]
        joints[.middleTip] = j(.middleTip, 0.5, CGFloat(fingerExtendedRatio))
        joints[.ringTip] = j(.ringTip, 0.75, CGFloat(fingerExtendedRatio))
        joints[.littleTip] = j(.littleTip, 1, CGFloat(fingerExtendedRatio))
        return joints
    }

    func testTightPinchWithCurledFingersIsNormalPinchNotOKSign() {
        // pinchDist 0.05 → ratio 0.05 (<1.98); tip/MCP 0.3 → 0.3 (<1.2 extended cutoff).
        let joints = makeJoints(pinchDist: 0.05, fingerExtendedRatio: 0.3)
        XCTAssertFalse(HandShapeClassifier.isOKSign(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testTightPinchWithExtendedFingersIsOKSign() {
        // pinchDist 0.05 -> tight pinch. finger ratio 2.0 -> clearly extended.
        let joints = makeJoints(pinchDist: 0.05, fingerExtendedRatio: 2.0)
        XCTAssertTrue(HandShapeClassifier.isOKSign(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testOpenHandWithExtendedFingersIsNotOKSign() {
        // pinchDist 7.0 -> ratio 7.0, above pinchThreshold 1.98: not pinching at all.
        let joints = makeJoints(pinchDist: 7.0, fingerExtendedRatio: 2.0)
        XCTAssertFalse(HandShapeClassifier.isOKSign(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    // MARK: - isPointing (relaxed middle/ring/little gate)

    /// palmWidth fixed at 1.0 (indexMCP-littleMCP). Thumb sits off to the side so thumb-index
    /// distance is always clearly "away" (>pinchEnterThreshold) regardless of index extension —
    /// isolates the finger-curl variables the relaxed gate cares about.
    private func makePointingJoints(
        indexRatio: Double,
        middleRatio: Double,
        ringRatio: Double,
        littleRatio: Double
    ) -> [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample] {
        func j(_ name: HumanHandPoseObservation.JointName, _ x: CGFloat, _ y: CGFloat) -> LandmarkFrame.JointSample {
            LandmarkFrame.JointSample(name: name, x: x, y: y, confidence: 1.0)
        }
        return [
            .indexMCP: j(.indexMCP, 0, 0),
            .littleMCP: j(.littleMCP, 1, 0),
            .thumbTip: j(.thumbTip, -1, 0),
            .indexTip: j(.indexTip, 0, CGFloat(indexRatio)),
            .middleMCP: j(.middleMCP, 0.5, 0),
            .middleTip: j(.middleTip, 0.5, CGFloat(middleRatio)),
            .ringMCP: j(.ringMCP, 0.75, 0),
            .ringTip: j(.ringTip, 0.75, CGFloat(ringRatio)),
            .littleTip: j(.littleTip, 1, CGFloat(littleRatio)),
        ]
    }

    func testCleanPointIsPointing() {
        // index extended, all three others clearly curled — the unambiguous case.
        let joints = makePointingJoints(indexRatio: 1.5, middleRatio: 0.3, ringRatio: 0.3, littleRatio: 0.3)
        XCTAssertTrue(HandShapeClassifier.isPointing(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testFistIsNotPointing() {
        // index curled along with everything else — fails at the index-extended guard.
        let joints = makePointingJoints(indexRatio: 0.3, middleRatio: 0.3, ringRatio: 0.3, littleRatio: 0.3)
        XCTAssertFalse(HandShapeClassifier.isPointing(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testOpenFlatHandIsNotPointing() {
        // everything extended — 0 of 3 curled, well below the "at least 2" relaxed floor.
        let joints = makePointingJoints(indexRatio: 1.5, middleRatio: 2.0, ringRatio: 2.0, littleRatio: 2.0)
        XCTAssertFalse(HandShapeClassifier.isPointing(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testOneAmbiguousMiddleFingerStillPointing() {
        // middle misreads as extended (weak-landmark jitter); ring + little clearly curled.
        // curledCount == 2, so the relaxed gate passes — the old "curled == 3 of 3" gate would not.
        let joints = makePointingJoints(indexRatio: 1.5, middleRatio: 2.0, ringRatio: 0.3, littleRatio: 0.3)
        XCTAssertTrue(HandShapeClassifier.isPointing(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }

    func testTwoAmbiguousFingersStillRejected() {
        // middle + ring both misread as extended — only 1 of 3 curled, below the "at least 2" floor.
        // The relaxed gate tolerates one bad landmark, not two: it isn't a free pass.
        let joints = makePointingJoints(indexRatio: 1.5, middleRatio: 2.0, ringRatio: 2.0, littleRatio: 0.3)
        XCTAssertFalse(HandShapeClassifier.isPointing(joints: joints, dyAspectCorrection: Self.noAspectCorrection))
    }
}
