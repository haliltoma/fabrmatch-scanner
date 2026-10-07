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
            project = try await store.load(projectID)
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
        let names = ["model.usdz", "room.usdz", "room.json", "pointcloud.ply", "splat/transforms.json"]
        return names.map { root.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func viewer(_ source: ViewerRequest.Source, title: String) -> ViewerRequest {
        let paths = store.paths(for: projectID)
        return ViewerRequest(title: title, source: source, measurementsURL: paths.measurements, thumbnailURL: paths.thumbnail)
    }

    /// Tapping a scan opens its mesh, or else its first viewable output.
    func defaultViewer(for scan: ScanRecord, projectName: String) -> ViewerRequest? {
        if hasMesh(scan) { return viewer(.meshChunks(scanPaths(scan).meshChunks), title: projectName) }
        if let file = outputs(of: scan).first(where: { ["usdz", "ply"].contains($0.pathExtension) }) {
            return viewer(.file(file), title: file.lastPathComponent)
        }
        return nil
    }

    func hasRawCapture(_ scan: ScanRecord) -> Bool {
        FileManager.default.fileExists(atPath: scanPaths(scan).capture.appendingPathComponent("capture.json").path)
    }

    /// Zips `raw/capture` (and Object Capture photos) for AirDrop to the Mac pipeline. Uses the system's
    /// coordinated "for uploading" read, which produces a zip of a directory without extra libraries.
    func zipRawCapture(_ scan: ScanRecord) async -> URL? {
        let source = scanPaths(scan).capture
        let name = "scan-\(scan.id.uuidString.prefix(8))-\(scan.mode.rawValue).zip"
        let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var outcome: Result<URL, Error> = .failure(CocoaError(.fileReadUnknown))
            NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { zipURL in
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destination)
                outcome = Result { try FileManager.default.copyItem(at: zipURL, to: destination); return destination }
            }
            if let coordinationError { return .failure(coordinationError) }
            return outcome
        }.value
        switch result {
        case .success(let url): return url
        case .failure(let error):
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func hasMesh(_ scan: ScanRecord) -> Bool {
        let chunks = scanPaths(scan).meshChunks
        return ((try? FileManager.default.contentsOfDirectory(atPath: chunks.path))?.isEmpty == false)
    }
}
