import Foundation
import Observation
import ScanLabCore
import UIKit

/// Drives one capture: lifecycle, HUD values, 10 s autosave, thermal policy (M3).
@Observable
final class ScanSessionModel {
    let request: ScanRequest
    private(set) var phase: ScanPhase = .preparing
    private(set) var warning: CaptureWarning?
    private(set) var triangleCount = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var thermal: ThermalLevel = .nominal
    private(set) var mode: LiDARMeshCaptureMode?

    private let store: ProjectStore
    private let settings: CaptureSettings
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0
    private var loops: [Task<Void, Never>] = []

    static let autosaveInterval: Duration = .seconds(10)

    init(request: ScanRequest, store: ProjectStore, settings: CaptureSettings) {
        self.request = request
        self.store = store
        self.settings = settings
    }

    func prepare() async {
        do {
            let record = ScanRecord(id: request.scanID, mode: request.mode, sensor: .lidar, createdAt: .now,
                                    device: UIDevice.current.model, qualityProfile: settings.quality)
            let paths = try await store.addScan(record, to: request.projectID)
            let mode = LiDARMeshCaptureMode(paths: paths, record: record) { [weak self] status in
                Task { @MainActor in self?.apply(status) }
            }
            try await mode.prepare(settings: settings)
            self.mode = mode
            phase = .ready
            startLoops(observing: mode)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func start() async {
        guard let mode else { return }
        do {
            try await mode.start()
            segmentStart = .now
            phase = .scanning
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func pause() async {
        guard let mode, phase == .scanning else { return }
        closeSegment()
        await mode.pause()
        phase = .paused
    }

    /// Saves the scan and returns the project to open, or nil on failure.
    func finish() async -> UUID? {
        guard let mode else { return nil }
        closeSegment()
        phase = .saving
        stopLoops()
        do {
            var artifact = try await mode.finish()
            if request.mode == .pointCloud {
                let capture = artifact.scanDirectory.appendingPathComponent("raw/capture")
                let output = artifact.scanDirectory.appendingPathComponent("pointcloud.ply")
                let count = try await Self.fusePointCloud(capture, output)
                artifact.record.stats.vertices = count
            }
            try await store.updateScan(artifact.record, in: request.projectID)
            phase = .finished
            return request.projectID
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Called when the screen goes away: never leave an AR session running behind it.
    func shutdown() {
        stopLoops()
        mode?.session.pause()
    }

    func discard() async {
        stopLoops()
        await mode?.cancel()
        try? await store.moveToTrash(request.projectID)
    }

    @concurrent
    private static func fusePointCloud(_ capture: URL, _ output: URL) async throws -> Int {
        try CapturePointCloud.write(captureDirectory: capture, to: output, voxelSize: 0.004)
    }

    // MARK: Background loops

    private func startLoops(observing mode: LiDARMeshCaptureMode) {
        loops.append(Task { [weak self] in
            for await state in mode.state {
                if case .warning(let w) = state { self?.warning = w }
            }
        })
        // Autosave + HUD counters (PRD §5.3 crash recovery every 10 s).
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tick()
            }
        })
        // FR-3.8 thermal policy.
        loops.append(Task { [weak self] in
            self?.handleThermal(ThermalLevel(ProcessInfo.processInfo.thermalState))
            for await _ in NotificationCenter.default.notifications(named: ProcessInfo.thermalStateDidChangeNotification) {
                self?.handleThermal(ThermalLevel(ProcessInfo.processInfo.thermalState))
            }
        })
    }

    private var ticks = 0

    private func tick() async {
        guard let mode else { return }
        elapsed = accumulated + (segmentStart.map { Date.now.timeIntervalSince($0) } ?? 0)
        triangleCount = await mode.store.stats.triangleCount
        ticks += 1
        if phase == .scanning, ticks % 10 == 0 {
            _ = try? await mode.autosave()
        }
    }

    private func handleThermal(_ level: ThermalLevel) {
        thermal = level
        switch ThermalPolicy.action(for: level) {
        case .proceed: if warning == .thermalSerious { warning = nil }
        case .warn: warning = .thermalSerious
        case .saveAndStop: Task { await pause() }
        }
    }

    private func apply(_ status: FrameStatus) {
        guard phase == .scanning else { return }
        if warning != .thermalSerious { warning = status.warning }
    }

    private func closeSegment() {
        if let start = segmentStart { accumulated += Date.now.timeIntervalSince(start) }
        segmentStart = nil
        elapsed = accumulated
    }

    private func stopLoops() {
        loops.forEach { $0.cancel() }
        loops.removeAll()
    }
}
