import Foundation
import Observation
import ScanLabCore

@Observable
final class ProjectDetailModel {
    let projectID: UUID
    private let store: ProjectStore
    private(set) var project: Project?
    private(set) var storage: StorageSummary?
    var errorMessage: String?

    init(projectID: UUID, store: ProjectStore) {
        self.projectID = projectID
        self.store = store
    }

    func load() async {
        do {
            // Aborted captures leave empty scan records; drop them so every row means something.
            for scan in try await store.load(projectID).scans where await store.isEmptyScan(scan, in: projectID) {
                try await store.removeScan(scan.id, from: projectID)
            }
            project = try await store.load(projectID)
            backfillFloorPlans()
            storage = try await store.storageSummary(for: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearRawFrames() async {
        do {
            try await store.clearRawFrames(for: projectID)
            storage = try await store.storageSummary(for: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanPaths(_ scan: ScanRecord) -> ScanPaths {
        store.paths(for: projectID).scan(scan.id)
    }

    var exportsDirectory: URL { store.paths(for: projectID).exports }

    /// Deliverables a capture mode wrote next to its scan (models, point clouds, plans, packages).
    func outputs(of scan: ScanRecord) -> [URL] {
        let root = scanPaths(scan).root
        let known = ["model.usdz", "room.usdz", "floorplan.pdf", "room.json", "pointcloud.ply", "splat/transforms.json"]
            .map { root.appendingPathComponent($0) }
        // Plus anything the user derived (crops, edits) next to them.
        let derived = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["ply", "usdz", "pdf"].contains($0.pathExtension) && !known.contains($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return (known + derived).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func viewer(_ source: ViewerRequest.Source, title: String, scan: ScanRecord? = nil) -> ViewerRequest {
        let paths = store.paths(for: projectID)
        var request = ViewerRequest(title: title, source: source, measurementsURL: paths.measurements, thumbnailURL: paths.thumbnail)
        request.outputDirectory = scan.map { scanPaths($0).root }
        return request
    }

    /// Tapping a scan opens its mesh, or else its first viewable output.
    func defaultViewer(for scan: ScanRecord, projectName: String) -> ViewerRequest? {
        if hasMesh(scan) { return viewer(.meshChunks(scanPaths(scan).meshChunks), title: projectName, scan: scan) }
        if let file = outputs(of: scan).first(where: { ["usdz", "ply"].contains($0.pathExtension) }) {
            return viewer(.file(file), title: file.lastPathComponent, scan: scan)
        }
        return nil
    }

    /// Room scans saved before floor plans existed get their PDF from room.json.
    private func backfillFloorPlans() {
        for scan in project?.scans ?? [] where scan.mode == .roomPlan {
            let root = scanPaths(scan).root
            let pdf = root.appendingPathComponent("floorplan.pdf"), json = root.appendingPathComponent("room.json")
            if !FileManager.default.fileExists(atPath: pdf.path), FileManager.default.fileExists(atPath: json.path) {
                try? FloorPlanRenderer.renderSaved(roomJSON: json, title: project?.name ?? "Kat planı", to: pdf)
            }
        }
    }

    /// What the project screen shows first: the newest scan that has something to look at.
    func primaryViewer(projectName: String) -> ViewerRequest? {
        for scan in (project?.scans ?? []).reversed() {
            if let v = defaultViewer(for: scan, projectName: projectName) { return v }
        }
        return nil
    }

    func hasRawCapture(_ scan: ScanRecord) -> Bool {
        FileManager.default.fileExists(atPath: scanPaths(scan).capture.appendingPathComponent("capture.json").path)
    }

    /// Object Capture photos; the phone only builds `.reduced` models, the Mac rebuilds them at full detail.
    func photos(of scan: ScanRecord) -> URL? {
        let images = scanPaths(scan).root.appendingPathComponent("images", isDirectory: true)
        let count = (try? FileManager.default.contentsOfDirectory(atPath: images.path).count) ?? 0
        return count > 0 ? images : nil
    }

    /// Zips `raw/capture` (or Object Capture photos) for AirDrop to the Mac pipeline. Uses the system's
    /// coordinated "for uploading" read, which produces a zip of a directory without extra libraries.
    func zipRawCapture(_ scan: ScanRecord) async -> URL? {
        let source = photos(of: scan) ?? scanPaths(scan).capture
        let name = "scan-\(scan.id.uuidString.prefix(8))-\(scan.mode.rawValue).zip"
        let result: Result<URL, Error> = await Self.zip(source, name)
        switch result {
        case .success(let url): return url
        case .failure(let error):
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @concurrent
    private static func zip(_ source: URL, _ name: String) async -> Result<URL, Error> {
        var coordinationError: NSError?
        var outcome: Result<URL, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { zipURL in
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            outcome = Result { try FileManager.default.copyItem(at: zipURL, to: destination); return destination }
        }
        if let coordinationError { return .failure(coordinationError) }
        return outcome
    }

    func hasMesh(_ scan: ScanRecord) -> Bool {
        let chunks = scanPaths(scan).meshChunks
        return ((try? FileManager.default.contentsOfDirectory(atPath: chunks.path))?.isEmpty == false)
    }
}
