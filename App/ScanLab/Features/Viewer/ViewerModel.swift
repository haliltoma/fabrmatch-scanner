import Foundation
import Observation
import SceneKit
import ScanLabCore

@Observable
final class ViewerModel {
    let request: ViewerRequest
    private(set) var content: ViewerContent?
    private(set) var error: String?
    var mode: DisplayMode = .shaded
    var measuring = false
    private(set) var measurements: [Measurement] = []
    private(set) var pendingPoint: SIMD3<Float>?
    /// Bumped to ask the scene view to re-fit the camera.
    private(set) var fitToken = 0
    var arPreview: URL?

    init(request: ViewerRequest) {
        self.request = request
    }

    private var key: String {
        switch request.source {
        case .meshChunks(let url), .file(let url): url.lastPathComponent == "mesh_chunks" ? "mesh" : url.lastPathComponent
        }
    }

    var modes: [DisplayMode] {
        switch content {
        case .mesh(let m): m.faceClassifications.isEmpty ? [.shaded, .wireframe, .points] : DisplayMode.allCases
        case .points: [.points]
        case .scene: [.shaded, .wireframe]
        case nil: []
        }
    }

    var canMeasure: Bool {
        if case .points = content { return false }
        return content != nil
    }

    func load() async {
        do {
            let loaded = try await ViewerLoader.load(request.source)
            content = loaded
            if case .points = loaded { mode = .points }
            if let url = request.measurementsURL { measurements = MeasurementFile.load(url, key: key) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fit() { fitToken += 1 }

    /// FR-11.1: first tap sets A, second tap completes the measurement.
    func tapped(world p: SIMD3<Float>) {
        guard measuring else { return }
        if let a = pendingPoint {
            measurements.append(Measurement(a: a, b: p))
            pendingPoint = nil
            persist()
        } else {
            pendingPoint = p
        }
    }

    func delete(_ m: Measurement) {
        measurements.removeAll { $0.id == m.id }
        persist()
    }

    func clearMeasurements() {
        measurements.removeAll()
        pendingPoint = nil
        persist()
    }

    private func persist() {
        guard let url = request.measurementsURL else { return }
        try? MeasurementFile.save(measurements, to: url, key: key)
    }

    /// AR Quick Look needs USDZ: use the file directly, or write the current scene out (FR-15.1, 1:1 scale).
    func prepareAR(scene: SCNScene?) {
        if case .file(let url) = request.source, url.pathExtension.lowercased() == "usdz" {
            arPreview = url
            return
        }
        guard let scene else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scanlab-preview-\(UUID().uuidString.prefix(8)).usdz")
        if scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) {
            arPreview = url
        } else {
            error = "AR önizlemesi için USDZ yazılamadı."
        }
    }
}
