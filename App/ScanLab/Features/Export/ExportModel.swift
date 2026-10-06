import Foundation
import Observation
import ScanLabCore
import ScanLabExport

/// Export wizard state (M13 / FR-13.1): merge chunks → write file → verify round-trip.
@Observable
final class ExportModel {
    let request: ExportRequest
    var format: ExportFormat = .stl
    var unit: LengthUnit = .millimeters
    var upAxis: UpAxis = .z
    private(set) var isExporting = false
    private(set) var result: ExportResult?
    var errorMessage: String?

    init(request: ExportRequest) {
        self.request = request
    }

    func export() async {
        isExporting = true
        defer { isExporting = false }
        let options = ExportOptions(unit: unit, upAxis: upAxis)
        let name = "\(request.projectName)-\(request.scan.id.uuidString.prefix(8)).\(format.fileExtension)"
            .replacingOccurrences(of: "/", with: "-")
        do {
            result = try await Self.run(chunks: request.chunks, to: request.exports.appendingPathComponent(name), format: format, options: options)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Heavy work off the main actor (ADR-0003).
    @concurrent
    private static func run(chunks: URL, to url: URL, format: ExportFormat, options: ExportOptions) async throws -> ExportResult {
        let store = MeshStore()
        _ = try await store.load(from: chunks)
        let mesh = MeshMerger.merge(await store.snapshot())
        try format.exporter.export(mesh, to: url, options: options)
        let verification = try ExportVerifier.verify(mesh, exportedTo: url, format: format, options: options)
        return ExportResult(url: url, triangles: mesh.triangleCount, verified: verification.passed)
    }
}

/// Created inside the `@concurrent` export job, hence nonisolated.
nonisolated struct ExportResult: Equatable, Sendable {
    let url: URL
    let triangles: Int
    let verified: Bool
}
