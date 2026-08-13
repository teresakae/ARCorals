import SwiftUI

/// Phase 4 HUD: planes + pinch calibration + gesture + raycast tier.
struct ARStatusHUD: View {
    @ObservedObject var session: ARSessionCoordinator

    var body: some View {
        VStack(spacing: 10) {
            // Always-visible controls: hide/show toggle + Torch button
            HStack {
                Spacer(minLength: 0)
                Button(action: { session.hudHidden.toggle() }) {
                    Image(systemName: session.hudHidden ? "eye" : "eye.slash")
                        .font(.caption)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .tint(.gray)

                Button(session.torchOn ? "Torch: On" : "Torch: Off") {
                    session.toggleTorch()
                }
                .buttonStyle(.bordered)
                .tint(session.torchOn ? .yellow : .gray)
            }

            demoModePicker

            // Main HUD content (hidden when hudHidden is true)
            if !session.hudHidden {
                if session.needsScanPrompt {
                    scanBanner
                }

                HStack(alignment: .top, spacing: 8) {
                    statusCard
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        toggle("Planes", isOn: $session.showPlaneVisualization, on: .teal)
                        toggle("Dots", isOn: $session.showLandmarks, on: .green)
                    }
                }

                calibrationBar
            }

            Spacer()
        }
        .padding(16)
        .padding(.top, 8)
    }

    private var scanBanner: some View {
        VStack(spacing: 6) {
            Text("Move your phone to scan the surface")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("No LiDAR — planes need a few seconds of deliberate panning.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(format: "Scanning… %.1fs", session.elapsedSeconds))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Planes: \(session.planeCount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if let t = session.secondsToFirstPlane {
                Text(String(format: "First plane: %.1fs", t))
                    .font(.caption.monospacedDigit())
            } else {
                Text("First plane: —")
                    .font(.caption.monospacedDigit())
            }
            Text("Gesture: \(session.gesturePhaseName)")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("Mode: \(session.manipulationModeName)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(modeColor(session.manipulationModeName))
            if session.demoMode == .point {
                Text("isPointing: \(session.debugIsPointing ? "yes" : "no")  target: \(session.debugPointTarget ? "hit" : "—")")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(session.debugIsPointing ? .green : .red)
            }
            Text("Wave: \(session.waveCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("Raycast: \(tierLabel(session.lastRaycastTier))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(tierColor(session.lastRaycastTier))
            Text("Tracking: \(session.trackingStateLabel)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(String(format: "Vision %.0fHz  rx %d / ok %d", session.inferenceHz, session.framesReceived, session.framesProcessed))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if let url = session.metrics.fileURL {
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var calibrationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("palmWidth")
                    .font(.caption.weight(.semibold))
                Text(ratioText(session.pinchRatio))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(ratioColor(session.pinchRatio))
                Text("thr \(String(format: "%.1f", session.tuning.pinchThreshold))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let mn = session.palmWidthMin, let mx = session.palmWidthMax {
                    Text(String(format: "2s %.2f–%.2f", mn, mx))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("Hold Open/Pinched to label ARFrame ratios (seam #2 check vs HandProbe ≈5.9).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                labelButton("Open", state: .open)
                labelButton("Pinched", state: .pinched)
                Button("Clear") { session.setGroundTruth(nil) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labelButton(_ title: String, state: GroundTruthState) -> some View {
        let active = session.groundTruth == state
        return Button(title) {
            session.setGroundTruth(active ? nil : state)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? (state == .pinched ? .orange : .blue) : .gray)
        .controlSize(.small)
    }

    /// Demo-mode pin: what a pinch means. Buttons (not Picker) — GESTURES.md §1.
    private var demoModePicker: some View {
        HStack(spacing: 6) {
            ForEach(ARSessionCoordinator.DemoMode.allCases, id: \.self) { mode in
                let active = session.demoMode == mode
                Button(mode.rawValue) {
                    session.demoMode = mode
                }
                .buttonStyle(.borderedProminent)
                .tint(active ? .purple : .gray)
                .controlSize(.small)
            }

            // Clear All — reset for Place mode's multi-object accumulate (GESTURES.md §1).
            Button("Clear All") {
                session.scene.clearAll()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>, on: Color) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.caption.weight(.semibold))
        }
        .toggleStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(isOn.wrappedValue ? on : .gray)
    }

    private func ratioText(_ r: Double?) -> String {
        guard let r else { return "—" }
        return String(format: "%.2f", r)
    }

    private func ratioColor(_ r: Double?) -> Color {
        guard let r else { return .secondary }
        if r < session.tuning.pinchEnterThreshold { return .orange }
        if r > session.tuning.pinchExitThreshold { return .blue }
        return .yellow
    }

    private func modeColor(_ name: String) -> Color {
        if name.hasSuffix("⏸") { return .red }
        if name.hasSuffix("✓") { return .green }
        switch name {
        case "SCALE": return .orange
        case "YAW": return .mint
        case "MOVE": return .cyan
        default: return .secondary
        }
    }

    private func tierLabel(_ tier: PlacementService.Tier) -> String {
        switch tier {
        case .existingPlaneGeometry: return "existingPlaneGeometry"
        case .existingPlaneInfinite: return "existingPlaneInfinite"
        case .estimatedPlane: return "estimatedPlane"
        case .none: return "none"
        }
    }

    private func tierColor(_ tier: PlacementService.Tier) -> Color {
        switch tier {
        case .existingPlaneGeometry: return .green
        case .existingPlaneInfinite: return .mint
        case .estimatedPlane: return .orange
        case .none: return .secondary
        }
    }
}
