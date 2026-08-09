import ARKit
import Foundation

/// Phase 4 CSV — gesture + plane + calibration rows.
final class MetricsLogger {
    enum Event: String {
        case sessionStart
        case firstPlane
        case planeUpdate
        case placement
        case gesture
        case calibration
        case frameStats
    }

    private(set) var fileURL: URL?
    private var handle: FileHandle?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var lastPlaneUpdateLog: Date?
    private let planeUpdateMinInterval: TimeInterval = 1.0

    var isLogging: Bool { handle != nil }

    func startNewFile() {
        stop()

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("phase4_join_\(Self.fileStamp()).csv")

        let header = """
        # phase=4 file=\(url.lastPathComponent)
        # device=\(Self.deviceModel()) ios=\(ProcessInfo.processInfo.operatingSystemVersionString)
        # pinchThreshold=\(GestureTuning.default.pinchThreshold) hysteresisBand=\(GestureTuning.default.hysteresisBand)
        # denominator=palmWidth seam=ARFrame.capturedImage orientation=.right
        # raycast_chain=existingPlaneGeometry>existingPlaneInfinite>estimatedPlane
        \(Self.csvColumns.joined(separator: ","))

        """

        do {
            try header.write(to: url, atomically: true, encoding: String.Encoding.utf8)
            let fh = try FileHandle(forWritingTo: url)
            try fh.seekToEnd()
            fileURL = url
            handle = fh
        } catch {
            fileURL = nil
            handle = nil
        }
    }

    func stop() {
        try? handle?.close()
        handle = nil
        lastPlaneUpdateLog = nil
    }

    func log(
        event: Event,
        secondsSinceStart: TimeInterval,
        planeCount: Int,
        planeExtentM2: Float,
        raycastTier: PlacementService.Tier,
        trackingState: ARCamera.TrackingState,
        gesturePhase: String = "",
        pinchRatio: Double? = nil,
        handCoveragePct: Double? = nil,
        framesReceived: Int = 0,
        framesProcessed: Int = 0,
        groundTruth: String = ""
    ) {
        guard let handle else { return }

        if event == .planeUpdate {
            let now = Date()
            if let last = lastPlaneUpdateLog, now.timeIntervalSince(last) < planeUpdateMinInterval {
                return
            }
            lastPlaneUpdateLog = now
        }

        let row = [
            dateFormatter.string(from: Date()),
            event.rawValue,
            String(format: "%.3f", secondsSinceStart),
            String(planeCount),
            String(format: "%.4f", planeExtentM2),
            raycastTier.rawValue,
            Self.trackingLabel(trackingState),
            gesturePhase,
            pinchRatio.map { String(format: "%.4f", $0) } ?? "",
            handCoveragePct.map { String(format: "%.1f", $0) } ?? "",
            String(framesReceived),
            String(framesProcessed),
            groundTruth,
            "", // placement_error_cm — ruler (TESTING Run C)
        ].joined(separator: ",") + "\n"

        if let data = row.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private static let csvColumns = [
        "timestamp",
        "event",
        "seconds_since_start",
        "plane_count",
        "plane_extent_m2",
        "raycast_tier",
        "tracking_state",
        "gesture_phase",
        "pinch_ratio_palmWidth",
        "hand_frame_coverage_pct",
        "frames_received",
        "frames_processed",
        "ground_truth",
        "placement_error_cm",
    ]

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    static func trackingLabel(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable: return "notAvailable"
        case .normal: return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited:initializing"
            case .excessiveMotion: return "limited:excessiveMotion"
            case .insufficientFeatures: return "limited:insufficientFeatures"
            case .relocalizing: return "limited:relocalizing"
            @unknown default: return "limited:unknown"
            }
        }
    }
}
