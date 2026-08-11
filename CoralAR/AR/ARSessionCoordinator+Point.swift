import CoreGraphics
import Foundation

/// Point-and-dwell dispatch. Feeds the index fingertip through
/// `HandShapeClassifier.isPointing` + `SceneController.selectAnnotation(at:)`
/// into `PointStateMachine`, and mirrors its events into the annotation
/// popup state.
extension ARSessionCoordinator {
    /// Called from `handleVision`, after carry/rotate routing. `frame` is nil on the
    /// dropped/nil-Vision-frame path — must still be fed so an in-flight dwell can time out.
    func handlePoint(frame: LandmarkFrame?, packet: FramePacket) {
        var target: AnnotationID?

        if let frame,
           HandShapeClassifier.isPointing(joints: frame.joints, confidenceGate: tuning.confidenceGate, tuning: tuning),
           let visionPoint = frame.indexTipPoint(confidenceGate: tuning.confidenceGate) {
            let viewPoint = LandmarkSpace.visionToViewport(
                visionPoint,
                displayTransform: packet.displayTransform,
                viewportSize: packet.viewportSize
            )
            target = scene.selectAnnotation(at: viewPoint)
        }

        let pinchActive: Bool
        switch stateMachine.phase {
        case .began, .changed:
            pinchActive = true
        default:
            pinchActive = false
        }

        let observation = PointObservation(timestamp: machineTime, target: target, pinchActive: pinchActive)
        let events = pointStateMachine.process(observation)
        dwellProgress = pointStateMachine.dwellProgress

        for event in events {
            switch event {
            case .hoverBegan(let id):
                activeAnnotationID = id
            case .hoverEnded(let id):
                if activeAnnotationID == id {
                    activeAnnotationID = nil
                }
            }
        }
    }
}
