import CoreGraphics
import Foundation

/// Point-and-dwell → popup; allowsPoint; nil target when off ends dwell (docs/GESTURES.md §2.9).
extension ARSessionCoordinator {
    /// After carry/rotate; nil frame still fed so dwell times out (docs/ARCHITECTURE.md §5 seam 5).
    func handlePoint(frame: LandmarkFrame?, packet: FramePacket) {
        var target: AnnotationID?

        if demoMode.allowsPoint,
           let frame,
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
