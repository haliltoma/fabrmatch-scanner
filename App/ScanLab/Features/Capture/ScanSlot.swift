import Foundation
import ScanLabCore
import UIKit

/// A registered scan inside a project: where a capture mode writes, and how it reports back.
/// Every mode follows the same lifecycle: `open` before capturing, `close` with final stats.
struct ScanSlot {
    let projectID: UUID
    var record: ScanRecord
    let paths: ScanPaths
    let store: ProjectStore

    static func open(_ request: ScanRequest, sensor: SensorKind, store: ProjectStore,
                     quality: QualityProfile = .balanced) async throws -> ScanSlot {
        let record = ScanRecord(id: request.scanID, mode: request.mode, sensor: sensor, createdAt: .now, device: UIDevice.current.model,
                                qualityProfile: quality, containsFace: request.mode == .trueDepth)
        let paths = try await store.addScan(record, to: request.projectID)
        return ScanSlot(projectID: request.projectID, record: record, paths: paths, store: store)
    }

    func close(stats: ScanStats) async throws {
        var r = record
        r.stats = stats
        try await store.updateScan(r, in: projectID)
    }

    func discard() async {
        try? await store.moveToTrash(projectID)
    }
}
