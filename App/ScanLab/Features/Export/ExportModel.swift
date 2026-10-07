import Foundation
import ModelIO
import Observation
import SceneKit
import ScanLabCore
import ScanLabExport

/// Export wizard (M13 / FR-13.1): load → convert → write to exports/ → verify (FR-13.5) → share.
@Observable
final class ExportModel {
    let request: ExportRequest
    private(set) var content: ViewerContent?
    private(set) var formats: [AppExportFormat] = []
    var format: AppExportFormat = .core(.stl)
    var unit: LengthUnit = .millimeters
    var upAxis: UpAxis = .z
    private(set) var isExporting = false
    private(set) var result: ExportResult?
    var errorMessage: String?

    init(request: ExportRequest) {
        self.request = request
    }

    func load() async {
        do {
            let loaded = try await ViewerLoader.load(request.source)
            content = loaded
            formats = AppExportFormat.available(for: loaded)
            if let first = formats.first { format = first }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export() async {
        guard let content else { return }
        isExporting = true
        defer { isExporting = false }
        let name = "\(request.baseName)-\(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))"
            .replacing(":", with: "").replacing("/", with: "-")
        let url = request.exports.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        do {
            try FileManager.default.createDirectory(at: request.exports, withIntermediateDirectories: true)
            switch (format, content) {
            case (.core(let f), .mesh(let mesh)):
                result = try await Self.writeCore(mesh, f, url, ExportOptions(unit: unit, upAxis: upAxis))
            case (.core(let f), .points(let points)):
                result = try await Self.writeCore(TriangleMesh(positions: points), f, url, ExportOptions(unit: unit, upAxis: upAxis))
            case (.usdz, .mesh):
                let scene = SCNScene()
                scene.rootNode.addChildNode(SceneBuilder.node(for: content, mode: .shaded))
                guard scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) else { throw CocoaError(.fileWriteUnknown) }
                result = ExportResult(url: url, summary: "USDZ", verified: FileManager.default.fileExists(atPath: url.path))
            case (.core, .scene):
                guard case .file(let source) = request.source else { return }
                try MDLAsset(url: source).export(to: url)
                result = ExportResult(url: url, summary: "Model I/O dönüşümü", verified: FileManager.default.fileExists(atPath: url.path))
            default:
                errorMessage = "Bu içerik bu biçime aktarılamıyor."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Heavy work off the main actor (ADR-0003).
    @concurrent
    private static func writeCore(_ mesh: TriangleMesh, _ format: ExportFormat, _ url: URL, _ options: ExportOptions) async throws -> ExportResult {
        try format.exporter.export(mesh, to: url, options: options)
        let check = try ExportVerifier.verify(mesh, exportedTo: url, format: format, options: options)
        let what = mesh.triangleCount > 0 && format != .xyz ? "\(mesh.triangleCount.formatted()) üçgen" : "\(mesh.vertexCount.formatted()) nokta"
        return ExportResult(url: url, summary: what, verified: check.passed)
    }
}

/// Created inside the `@concurrent` export job, hence nonisolated.
nonisolated struct ExportResult: Equatable, Sendable {
    let url: URL
    let summary: String
    let verified: Bool
}
