import SwiftUI
import Vision

struct LiveReadoutView: View {
    let result: HandPoseResult?
    let ratios: PinchRatioCalculator.Ratios?
    let fps: Double
    let distanceCm: Binding<Int>
    let rigNotes: Binding<String>
    let logCondition: Binding<String>
    let isLogging: Bool
    let logFileName: String
    let statusMessage: String
    let groundTruth: GroundTruthState?
    let wristBand: (min: Double?, max: Double?)
    let bboxBand: (min: Double?, max: Double?)
    let palmBand: (min: Double?, max: Double?)
    let onToggleLogging: () -> Void
    let onSetGroundTruth: (GroundTruthState) -> Void
    let onClearGroundTruth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("dist \(distanceCm.wrappedValue)cm")
                Stepper("", value: distanceCm, in: 20...80, step: 10)
                    .labelsHidden()
                Spacer()
                Button(isLogging ? "Stop CSV" : "Start CSV") {
                    onToggleLogging()
                }
                .buttonStyle(.borderedProminent)
                .tint(isLogging ? .red : .green)
            }

            TextField("condition (filename)", text: logCondition)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            TextField("Rig notes (CSV header)", text: rigNotes)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            Text(statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !logFileName.isEmpty {
                Text(logFileName)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
            }

            // Ground-truth labeling — prefer assistant / foot switch, not the measured hand.
            HStack(spacing: 8) {
                Text("label")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("OPEN") { onSetGroundTruth(.open) }
                    .buttonStyle(.borderedProminent)
                    .tint(groundTruth == .open ? .blue : .gray)
                Button("PINCHED") { onSetGroundTruth(.pinched) }
                    .buttonStyle(.borderedProminent)
                    .tint(groundTruth == .pinched ? .orange : .gray)
                Button("clear") { onClearGroundTruth() }
                    .font(.caption)
                Spacer()
                Text(groundTruth?.rawValue.uppercased() ?? "UNLABELED")
                    .font(.caption.monospaced().weight(.bold))
            }

            Divider()

            ratioRow("r_wrist", ratios?.wristMCP, wristBand)
            ratioRow("r_bbox", ratios?.bboxDiag, bboxBand)
            ratioRow("r_palm", ratios?.palmWidth, palmBand)
            gridRow("raw t-i", opt(ratios?.rawThumbIndexDist))

            Divider()

            let obs = result
            gridRow("obs", obs.map { "\($0.observationCount)" } ?? "—")
            gridRow("obs conf", format(obs?.observationConfidence))
            gridRow("fps", String(format: "%.1f", fps))
            gridRow("wrist c", jointLine(obs, .wrist))
            gridRow("thumbTip", jointLine(obs, .thumbTip))
            gridRow("indexTip", jointLine(obs, .indexTip))
            gridRow("thermal", thermal())
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private func ratioRow(
        _ label: String,
        _ value: Double?,
        _ band: (min: Double?, max: Double?)
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(opt(value))
                .font(.caption.monospaced().weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(bandText(band))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bandText(_ band: (min: Double?, max: Double?)) -> String {
        switch (band.min, band.max) {
        case let (min?, max?):
            return String(format: "2s [%.3f … %.3f]", min, max)
        default:
            return "2s [—]"
        }
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func jointLine(_ result: HandPoseResult?, _ name: HumanHandPoseObservation.JointName) -> String {
        guard let j = result?.joints[name] else { return "—" }
        return String(format: "c=%.2f", j.confidence)
    }

    private func format(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    private func opt(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }

    private func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "?"
        }
    }
}
