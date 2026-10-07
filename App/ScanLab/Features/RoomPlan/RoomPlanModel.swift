import Foundation
import Observation
import RoomPlan
import ScanLabCore

/// RoomPlan capture (PRD M6): live room capture, then parametric USDZ + JSON in the scan folder.
@Observable
final class RoomPlanModel {
    enum Phase: Equatable { case preparing, scanning, processing, review, saving, failed(String) }

    let request: ScanRequest
    private(set) var phase: Phase = .preparing
    private(set) var summary: String?
    private let store: ProjectStore
    private var slot: ScanSlot?
    private var startedAt = Date.now
    private var room: CapturedRoom?

    init(request: ScanRequest, store: ProjectStore) {
        self.request = request
        self.store = store
    }

    func prepare() async {
        guard RoomCaptureSession.isSupported else {
            phase = .failed("Bu cihaz RoomPlan'ı desteklemiyor (LiDAR gerekir).")
            return
        }
        do {
            slot = try await ScanSlot.open(request, sensor: .lidar, store: store)
            startedAt = .now
            phase = .scanning
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopRequested() { phase = .processing }

    func processed(_ room: CapturedRoom?, error: Error?) {
        guard let room else {
            phase = .failed(error?.localizedDescription ?? "Oda işlenemedi.")
            return
        }
        self.room = room
        let area = room.floors.reduce(Float(0)) { $0 + $1.dimensions.x * $1.dimensions.z }
        summary = "\(room.walls.count) duvar · \(room.doors.count) kapı · \(room.windows.count) pencere · "
            + "\(room.objects.count) mobilya · zemin ≈ \(area.formatted(.number.precision(.fractionLength(1)))) m²"
        phase = .review
    }

    func save() async -> UUID? {
        guard let slot, let room else { return nil }
        phase = .saving
        do {
            try room.export(to: slot.paths.root.appendingPathComponent("room.usdz"), exportOptions: .parametric)
            let json = JSONEncoder()
            json.outputFormatting = [.prettyPrinted, .sortedKeys]
            try json.encode(room).write(to: slot.paths.root.appendingPathComponent("room.json"), options: .atomic)
            try FloorPlanRenderer.render(room, title: "Kat planı", to: slot.paths.root.appendingPathComponent("floorplan.pdf"))
            try await slot.close(stats: ScanStats(vertices: 0, triangles: 0, durationSec: Date.now.timeIntervalSince(startedAt).rounded()))
            return slot.projectID
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    func discard() async { await slot?.discard() }
}
