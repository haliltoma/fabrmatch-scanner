import ARKit
import Foundation
import Observation
import ScanLabCore
import ScanLabExport

/// TrueDepth capture (PRD M21 mode B): front depth + world-tracked pose → raw SLDF frames for the
/// Mac's multi-algorithm reconstruction, plus an instant point-cloud preview on the phone.
@Observable
final class TrueDepthModel {
    enum Phase: Equatable { case preparing, ready, recording, paused, saving, finished, failed(String) }

    let request: ScanRequest
    private(set) var phase: Phase = .preparing
    private(set) var status = TrueDepthStatus(depthFrames: 0, distance: nil, keyframes: 0, points: 0)
    let session = ARSession()

    private let store: ProjectStore
    private var slot: ScanSlot?
    private var recorder: TrueDepthRecorder?
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    init(request: ScanRequest, store: ProjectStore) {
        self.request = request
        self.store = store
    }

    var guidance: String? {
        guard phase == .recording || phase == .ready || phase == .paused else { return nil }
        if status.depthFrames == 0 { return "TrueDepth verisi bekleniyor…" }
        guard let d = status.distance else { return "Parçayı ön kameraya göster (20–40 cm)" }
        if d < 0.18 { return "Biraz uzaklaş (\(Int(d * 100)) cm)" }
        if d > 0.45 { return "Yaklaş (\(Int(d * 100)) cm) — ideal 20–40 cm" }
        return nil
    }

    func prepare() async {
        guard ARFaceTrackingConfiguration.isSupported else {
            phase = .failed("Bu cihazda TrueDepth kamera yok.")
            return
        }
        guard ARFaceTrackingConfiguration.supportsWorldTracking else {
            phase = .failed("Bu cihaz ön kamerayla dünya takibini desteklemiyor; kareler konumlanamaz.")
            return
        }
        do {
            let slot = try await ScanSlot.open(request, sensor: .trueDepth, store: store, quality: .high)
            let recorder = TrueDepthRecorder(writer: CaptureWriter(directory: slot.paths.capture, sensor: .trueDepth)) { [weak self] s in
                Task { @MainActor in self?.status = s }
            }
            session.delegate = recorder
            session.delegateQueue = recorder.queue
            let config = ARFaceTrackingConfiguration()
            config.isWorldTrackingEnabled = true
            config.maximumNumberOfTrackedFaces = 1
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.slot = slot
            self.recorder = recorder
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func toggle() {
        switch phase {
        case .ready, .paused:
            recorder?.setRecording(true)
            startedAt = .now
            phase = .recording
        case .recording:
            recorder?.setRecording(false)
            closeSegment()
            phase = .paused
        default:
            break
        }
    }

    func finish() async -> UUID? {
        guard let slot, let recorder else { return nil }
        recorder.setRecording(false)
        closeSegment()
        phase = .saving
        session.pause()
        do {
            let points = try await Self.writePreview(recorder, to: slot.paths.root.appendingPathComponent("pointcloud.ply"))
            try await flushManifest(slot)
            try await slot.close(stats: ScanStats(vertices: points.count, triangles: 0, durationSec: accumulated.rounded()))
            phase = .finished
            return slot.projectID
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    func shutdown() { session.pause() }

    /// Fused preview cloud → pointcloud.ply (mm, Y up: opens in MeshLab/CloudCompare and the Mac engine).
    @concurrent
    private static func writePreview(_ recorder: TrueDepthRecorder, to url: URL) async throws -> [SIMD3<Float>] {
        let points = recorder.fusedPoints()
        try PLYBinaryExporter().export(TriangleMesh(positions: points), to: url, options: ExportOptions(unit: .millimeters, upAxis: .y))
        return points
    }

    func discard() async {
        session.pause()
        await slot?.discard()
    }

    /// Rewrites capture.json from the frames on disk (the recorder's writer may still be appending).
    private func flushManifest(_ slot: ScanSlot) async throws {
        let depthDir = slot.paths.capture.appendingPathComponent("depth")
        try await Task.sleep(for: .milliseconds(300))  // let the last detached appends land
        let names = (try? FileManager.default.contentsOfDirectory(atPath: depthDir.path))?
            .filter { $0.hasSuffix(".sldf") }.sorted().map { "depth/" + $0 } ?? []
        guard !names.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let manifest = CaptureManifest(sensor: .trueDepth, frames: names)
        try JSONEncoder().encode(manifest).write(to: slot.paths.capture.appendingPathComponent("capture.json"), options: .atomic)
    }

    private func closeSegment() {
        if let s = startedAt { accumulated += Date.now.timeIntervalSince(s) }
        startedAt = nil
    }
}
