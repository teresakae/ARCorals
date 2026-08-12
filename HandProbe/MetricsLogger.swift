import Foundation
import Vision

/// Appends CSV rows to Documents/. Phase 0 schema + Phase 1 pinch columns.
final class MetricsLogger {
    private(set) var fileURL: URL?
    private var handle: FileHandle?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var isLogging: Bool { handle != nil }

    func startNewFile(condition: String, rigNotes: String, distanceCm: Int) throws {
        stop()

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let stamp = Self.fileStamp()
        let safeCondition = condition
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = docs.appendingPathComponent("phase1_\(safeCondition)_\(stamp).csv")

        let device = Self.deviceModel()
        let ios = ProcessInfo.processInfo.operatingSystemVersionString
        let safeNotes = rigNotes.replacingOccurrences(of: "\n", with: " ")
        let header = """
        # phase=1 condition=\(safeCondition) file=\(url.lastPathComponent)
        # device=\(device) ios=\(ios)
        # rig=\(safeNotes)
        # initial_distance_cm=\(distanceCm)
        # confidence_gate=\(GestureTuning.default.confidenceGate)
        # coords=Vision NormalizedPoint after orientation:.right ; origin=bottom-left ; units=normalized
        # no pinch threshold — measurement only
        \(Self.csvColumns.joined(separator: ","))

        """

        try header.write(to: url, atomically: true, encoding: .utf8)
        let fh = try FileHandle(forWritingTo: url)
        try fh.seekToEnd()
        fileURL = url
        handle = fh
    }

    func stop() {
        try? handle?.close()
        handle = nil
    }

    func log(
        result: HandPoseResult,
        ratios: PinchRatioCalculator.Ratios,
        groundTruth: GroundTruthState?,
        distanceCm: Int,
        thermalState: ProcessInfo.ThermalState,
        fps: Double
    ) {
        guard let handle else { return }

        var fields: [String] = [
            dateFormatter.string(from: result.timestamp),
            String(distanceCm),
            String(result.observationCount),
            String(format: "%.4f", result.observationConfidence),
        ]

        for name in LandmarkFrame.jointNames {
            if let j = result.joints[name] {
                fields.append(String(format: "%.6f", j.x))
                fields.append(String(format: "%.6f", j.y))
                fields.append(String(format: "%.4f", j.confidence))
            } else {
                fields.append("")
                fields.append("")
                fields.append("")
            }
        }

        let chirality: String
        if result.chirality == .left {
            chirality = "left"
        } else if result.chirality == .right {
            chirality = "right"
        } else {
            chirality = ""
        }

        fields.append(chirality)
        fields.append(Self.thermalLabel(thermalState))
        fields.append(String(format: "%.2f", fps))

        fields.append(Self.opt(ratios.wristMCP))
        fields.append(Self.opt(ratios.bboxDiag))
        fields.append(Self.opt(ratios.palmWidth))
        fields.append(Self.opt(ratios.rawThumbIndexDist))
        fields.append(groundTruth?.rawValue ?? "")

        let line = fields.joined(separator: ",") + "\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    static let csvColumns: [String] = {
        var cols = ["timestamp", "distance_cm", "observation_count", "observation_confidence"]
        for name in LandmarkFrame.jointNames {
            let key = name.rawValue
            cols.append(contentsOf: ["\(key)_x", "\(key)_y", "\(key)_conf"])
        }
        cols.append(contentsOf: [
            "chirality", "thermal_state", "fps",
            "pinch_ratio_wristMCP", "pinch_ratio_bboxDiag", "pinch_ratio_palmWidth",
            "raw_thumb_index_dist", "ground_truth_state",
        ])
        return cols
    }()

    private static func opt(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", value)
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
