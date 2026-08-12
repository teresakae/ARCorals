import Foundation
import Vision
import XCTest
@testable import HandProbe

final class HandShapeClassifierTests: XCTestCase {
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
        XCTAssertFalse(HandShapeClassifier.isOKSign(joints: joints))
    }

    func testTightPinchWithExtendedFingersIsOKSign() {
        // pinchDist 0.05 -> tight pinch. finger ratio 2.0 -> clearly extended.
        let joints = makeJoints(pinchDist: 0.05, fingerExtendedRatio: 2.0)
        XCTAssertTrue(HandShapeClassifier.isOKSign(joints: joints))
    }

    func testOpenHandWithExtendedFingersIsNotOKSign() {
        // pinchDist 7.0 -> ratio 7.0, above pinchThreshold 1.98: not pinching at all.
        let joints = makeJoints(pinchDist: 7.0, fingerExtendedRatio: 2.0)
        XCTAssertFalse(HandShapeClassifier.isOKSign(joints: joints))
    }
}
