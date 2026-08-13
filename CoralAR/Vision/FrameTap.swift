import CoreGraphics
import CoreVideo
import Foundation
import ARKit
import UIKit
import Vision

/// Pixel buffer snapshot. Releases ARFrame immediately after capture.
struct FramePacket: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let imageResolution: CGSize
    let timestamp: TimeInterval
    /// Vision `orientation:` for this frame — derived once from the interface orientation live
    /// at capture, not hardcoded. See `LandmarkSpace.visionOrientation(for:)`.
    let visionOrientation: CGImagePropertyOrientation
    /// `imageResolution` after Vision's rotation — the size `LandmarkSpace.visionToViewport`
    /// aspect-fills against. See `LandmarkSpace.uprightImageSize(_:orientation:)`.
    let uprightImageSize: CGSize
    /// Aspect de-skew for gesture ratio math, matching `visionOrientation`. See
    /// `LandmarkSpace.dyAspectCorrection(for:orientation:)`.
    let dyAspectCorrection: Double
}

/// Throttle + drop-if-busy gate. Only place ARFrame is read for Vision.
struct FrameTap: Sendable {
    var inferenceInterval: TimeInterval = GestureTuning.default.inferenceInterval

    private var lastInferenceTime: TimeInterval = 0
    private var inFlight = false

    /// Snapshot buffer now; caller must call `markCompleted()` after Vision.
    mutating func tryBegin(
        frame: ARFrame,
        interfaceOrientation: UIInterfaceOrientation
    ) -> FramePacket? {
        guard !inFlight else { return nil }
        let t = frame.timestamp
        guard t - lastInferenceTime >= inferenceInterval else { return nil }

        inFlight = true
        lastInferenceTime = t

        let visionOrientation = LandmarkSpace.visionOrientation(for: interfaceOrientation)
        let imageResolution = frame.camera.imageResolution
        return FramePacket(
            pixelBuffer: frame.capturedImage,
            imageResolution: imageResolution,
            timestamp: t,
            visionOrientation: visionOrientation,
            uprightImageSize: LandmarkSpace.uprightImageSize(imageResolution, orientation: visionOrientation),
            dyAspectCorrection: LandmarkSpace.dyAspectCorrection(for: visionOrientation, imageResolution: imageResolution)
        )
    }

    mutating func markCompleted() {
        inFlight = false
    }
}
