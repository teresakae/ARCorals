import CoreGraphics
import CoreVideo
import Foundation
import ARKit
import UIKit

/// Pixel buffer + displayTransform snapshot. Releases ARFrame immediately after capture.
struct FramePacket: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let displayTransform: CGAffineTransform
    let viewportSize: CGSize
    let imageResolution: CGSize
    let timestamp: TimeInterval
}

/// Throttle + drop-if-busy gate. Only place ARFrame is read for Vision.
struct FrameTap: Sendable {
    var inferenceInterval: TimeInterval = GestureTuning.default.inferenceInterval

    private var lastInferenceTime: TimeInterval = 0
    private var inFlight = false

    /// Snapshot buffer + `displayTransform` now; caller must call `markCompleted()` after Vision.
    mutating func tryBegin(
        frame: ARFrame,
        viewportSize: CGSize,
        interfaceOrientation: UIInterfaceOrientation = .landscapeRight
    ) -> FramePacket? {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return nil }
        guard !inFlight else { return nil }
        let t = frame.timestamp
        guard t - lastInferenceTime >= inferenceInterval else { return nil }

        inFlight = true
        lastInferenceTime = t

        let transform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
        return FramePacket(
            pixelBuffer: frame.capturedImage,
            displayTransform: transform,
            viewportSize: viewportSize,
            imageResolution: frame.camera.imageResolution,
            timestamp: t
        )
    }

    mutating func markCompleted() {
        inFlight = false
    }
}
