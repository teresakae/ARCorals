import SwiftUI

/// On-screen Phase 3 HUD: plane count, time-to-first-plane, raycast tier, plane-viz toggle.
struct ARStatusHUD: View {
    @ObservedObject var session: ARSessionCoordinator

    var body: some View {
        VStack(spacing: 12) {
            if session.needsScanPrompt {
                scanBanner
            }

            HStack(alignment: .top) {
                statusCard
                Spacer()
                Toggle(isOn: $session.showPlaneVisualization) {
                    Text("Planes")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(session.showPlaneVisualization ? .teal : .gray)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Planes: \(session.planeCount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())

            if let t = session.secondsToFirstPlane {
                Text(String(format: "First plane: %.1fs", t))
                    .font(.caption.monospacedDigit())
            } else {
                Text("First plane: —")
                    .font(.caption.monospacedDigit())
            }

            Text("Raycast: \(tierLabel(session.lastRaycastTier))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(tierColor(session.lastRaycastTier))

            Text("Tracking: \(session.trackingStateLabel)")
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
