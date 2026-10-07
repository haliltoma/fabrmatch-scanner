import Foundation
import Observation
import SceneKit
import ScanLabCore
import ScanLabExport

@Observable
final class ViewerModel {
    let request: ViewerRequest
    private(set) var content: ViewerContent?
    /// Bumped whenever `content` is replaced, so the scene rebuilds.
    private(set) var contentVersion = 0
    private var original: ViewerContent?
    var showBox = false
    var cropping = false
    /// Crop handles as fractions (0…1) of the original bounds, per axis.
    var cropLower = SIMD3<Double>(0, 0, 0)
    var cropUpper = SIMD3<Double>(1, 1, 1)
    private(set) var savedCrop: URL?
    private(set) var error: String?
    var mode: DisplayMode = .shaded
    var measuring = false
    private(set) var measurements: [Measurement] = []
    private(set) var pendingPoint: SIMD3<Float>?
    /// Bumped to ask the scene view to re-fit the camera.
    private(set) var fitToken = 0
    var arPreview: SharedFile?

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
            original = loaded
            contentVersion += 1
            if case .points = loaded { mode = .points }
            if let url = request.measurementsURL { measurements = MeasurementFile.load(url, key: key) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fit() { fitToken += 1 }

    // MARK: Bounding box & crop (FR-10.6, FR-9.9)

    var canCrop: Bool {
        switch original {
        case .mesh, .points: return true
        default: return false
        }
    }

    private var originalMesh: TriangleMesh? {
        switch original {
        case .mesh(let m): m
        case .points(let p): TriangleMesh(positions: p)
        default: nil
        }
    }

    var originalBounds: BoundingBox? { originalMesh?.bounds }

    /// The crop region in world space, from the slider fractions.
    var cropBox: BoundingBox? {
        guard let b = originalBounds else { return nil }
        return MeshCropper.box(in: b, lower: SIMD3<Float>(cropLower), upper: SIMD3<Float>(cropUpper))
    }

    /// Live preview of the crop (called when a slider is released).
    func applyCropPreview() async {
        guard let mesh = originalMesh, let box = cropBox, let original else { return }
        let isPoints: Bool = { if case .points = original { return true } else { return false } }()
        let cropped = await Self.crop(mesh, box)
        content = isPoints ? .points(cropped.positions) : .mesh(cropped)
        contentVersion += 1
    }

    @concurrent
    private static func crop(_ mesh: TriangleMesh, _ box: BoundingBox) async -> TriangleMesh {
        MeshCropper.crop(mesh, to: box)
    }

    @concurrent
    private static func writePLY(_ mesh: TriangleMesh, _ url: URL) async throws {
        try PLYBinaryExporter().export(mesh, to: url, options: ExportOptions(unit: .millimeters, upAxis: .y))
    }

    func resetCrop() {
        cropLower = SIMD3(0, 0, 0)
        cropUpper = SIMD3(1, 1, 1)
        content = original
        contentVersion += 1
    }

    /// Saves the cropped result as a new PLY next to the scan (mm, Y up) and keeps editing from it.
    func saveCrop() async {
        guard let dir = request.outputDirectory, let content else { return }
        let mesh: TriangleMesh
        switch content {
        case .mesh(let m): mesh = m
        case .points(let p): mesh = TriangleMesh(positions: p)
        default: return
        }
        let url = dir.appendingPathComponent("kirpilmis-\(Date.now.formatted(.dateTime.hour().minute().second()).replacing(":", with: "")).ply")
        do {
            try await Self.writePLY(mesh, url)
            savedCrop = url
            original = content
            cropLower = SIMD3(0, 0, 0)
            cropUpper = SIMD3(1, 1, 1)
            cropping = false
        } catch {
            self.error = error.localizedDescription
        }
    }

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
            arPreview = SharedFile(url: url)
            return
        }
        guard let scene else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scanlab-preview-\(UUID().uuidString.prefix(8)).usdz")
        if scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) {
            arPreview = SharedFile(url: url)
        } else {
            error = "AR önizlemesi için USDZ yazılamadı."
        }
    }
}
