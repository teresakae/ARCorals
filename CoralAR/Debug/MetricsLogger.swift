import ARKit
import Foundation

/// Phase 5 CSV — gesture/placement/manipulation rows; rig + reporting in GESTURES.md.
final class MetricsLogger {
    enum Event: String {
        case sessionStart
        case firstPlane
        case planeUpdate
        case placement
        case gesture
        case calibration
        case frameStats
        case manipulation
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
    private var gestureSerial = 0
    private(set) var currentGestureID = 0

    var isLogging: Bool { handle != nil }

    func startNewFile() {
        stop()
        gestureSerial = 0
        currentGestureID = 0

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("phase5_manip_\(Self.fileStamp()).csv")

        let header = """
        # phase=5 file=\(url.lastPathComponent)
        # device=\(Self.deviceModel()) ios=\(ProcessInfo.processInfo.operatingSystemVersionString)
        # pinchThreshold=\(GestureTuning.default.pinchThreshold) hysteresisBand=\(GestureTuning.default.hysteresisBand)
        # scaleDeadzoneLog=\(GestureTuning.default.scaleDeadzoneLog) yawDeadzoneRad=\(GestureTuning.default.yawDeadzoneRad)
        # scaleSensitivity=\(GestureTuning.default.scaleSensitivity) yawSensitivity=\(GestureTuning.default.yawSensitivity)
        # scaleModeExitThreshold=\(GestureTuning.default.scaleModeExitThreshold)
        # denominator=palmWidth seam=ARFrame.capturedImage orientation=.right
        # mode_lock=dominant_axis_first_deadzone_crossing
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

    func beginGesture() -> Int {
        gestureSerial += 1
        currentGestureID = gestureSerial
        return currentGestureID
    }

    func endGesture() {
        currentGestureID = 0
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
        groundTruth: String = "",
        gestureID: Int? = nil,
        pinchRatioAtBegan: Double? = nil,
        scaleFactor: Float? = nil,
        yawAngle2D: Double? = nil,
        yawPalmAxis: Double? = nil,
        horizontalSlide: Double? = nil,
        yawAtBegan: Double? = nil,
        appliedYawRad: Float? = nil,
        mode: String = "",
        overshootCount: String = "",
        finalError: String = ""
    ) {
        guard let handle else { return }

        if event == .planeUpdate {
            let now = Date()
            if let last = lastPlaneUpdateLog, now.timeIntervalSince(last) < planeUpdateMinInterval {
                return
            }
            lastPlaneUpdateLog = now
        }

        let gid = gestureID ?? (currentGestureID == 0 ? nil : currentGestureID)

        var cols: [String] = []
        cols.append(dateFormatter.string(from: Date()))
        cols.append(event.rawValue)
        cols.append(String(format: "%.3f", secondsSinceStart))
        cols.append(String(planeCount))
        cols.append(String(format: "%.4f", planeExtentM2))
        cols.append(raycastTier.rawValue)
        cols.append(Self.trackingLabel(trackingState))
        cols.append(gesturePhase)
        cols.append(pinchRatio.map { String(format: "%.4f", $0) } ?? "")
        cols.append(handCoveragePct.map { String(format: "%.1f", $0) } ?? "")
        cols.append(String(framesReceived))
        cols.append(String(framesProcessed))
        cols.append(groundTruth)
        cols.append("") // placement_error_cm — ruler-measured column, per ADR-016; not populated on the live path
        cols.append(gid.map(String.init) ?? "")
        cols.append(pinchRatioAtBegan.map { String(format: "%.4f", $0) } ?? "")
        cols.append(scaleFactor.map { String(format: "%.4f", $0) } ?? "")
        cols.append(yawAngle2D.map { String(format: "%.4f", $0) } ?? "")
        cols.append(yawPalmAxis.map { String(format: "%.4f", $0) } ?? "")
        cols.append(yawAtBegan.map { String(format: "%.4f", $0) } ?? "")
        cols.append(appliedYawRad.map { String(format: "%.4f", $0) } ?? "")
        cols.append(mode)
        cols.append(overshootCount)
        cols.append(finalError)
        cols.append(horizontalSlide.map { String(format: "%.4f", $0) } ?? "")

        let row = cols.joined(separator: ",") + "\n"
        if let data = row.data(using: String.Encoding.utf8) {
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
        "gesture_id",
        "pinch_ratio_at_began",
        "scale_factor",
        "yaw_angle_2d",
        "yaw_palm_axis",
        "yaw_at_began",
        "applied_yaw_rad",
        "mode",
        "overshoot_count",
        "final_error",
        "horizontal_slide",
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
