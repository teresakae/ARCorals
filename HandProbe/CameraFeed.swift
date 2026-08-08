import AVFoundation
import CoreVideo
import UIKit

/// Rear-camera capture. Data-output buffers stay in native sensor orientation
/// (rotation angle 0) so Vision can use `orientation: .right`, matching ARKit.
final class CameraFeed: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "handprobe.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()

    var onFrame: ((CVPixelBuffer) -> Void)?

    private(set) var isRunning = false

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureIfNeeded()
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.isRunning = true
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.isRunning = false
        }
    }

    private var didConfigure = false

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "handprobe.camera.frames"))

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            // Native sensor orientation — do not rotate the buffer.
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }

        session.commitConfiguration()
    }
}

extension CameraFeed: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
