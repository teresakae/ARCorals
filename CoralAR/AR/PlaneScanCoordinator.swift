import ARKit
import Foundation

/// Scan-prompt until first confirmed plane — required without LiDAR (AGENTS.md).
@MainActor
final class PlaneScanCoordinator {
    private(set) var sessionStart: Date?
    private(set) var firstPlaneAt: Date?
    private var planeExtents: [UUID: Float] = [:]

    var needsScanPrompt: Bool { firstPlaneAt == nil }
    var planeCount: Int { planeExtents.count }

    var secondsToFirstPlane: TimeInterval? {
        guard let start = sessionStart, let first = firstPlaneAt else { return nil }
        return first.timeIntervalSince(start)
    }

    var secondsSinceStart: TimeInterval {
        guard let start = sessionStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var totalExtentM2: Float {
        planeExtents.values.reduce(0, +)
    }

    func sessionDidStart() {
        sessionStart = Date()
        firstPlaneAt = nil
        planeExtents.removeAll()
    }

    /// Returns `true` the moment the first confirmed horizontal plane appears.
    @discardableResult
    func ingest(planeAnchors: [ARPlaneAnchor]) -> Bool {
        let wasEmpty = planeExtents.isEmpty

        for plane in planeAnchors where plane.alignment == .horizontal {
            let e = plane.planeExtent
            planeExtents[plane.identifier] = e.width * e.height
        }

        if wasEmpty, !planeExtents.isEmpty {
            firstPlaneAt = Date()
            return true
        }
        return false
    }

    func remove(planeAnchors: [ARPlaneAnchor]) {
        for plane in planeAnchors {
            planeExtents.removeValue(forKey: plane.identifier)
        }
        if planeExtents.isEmpty {
            // Lost all planes — show scan prompt again (common on blank/glossy desks).
            firstPlaneAt = nil
        }
    }
}
