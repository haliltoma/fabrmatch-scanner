import Foundation
import ScanLabCore
import ScanLabExport
import SceneKit

/// Loads any scan output into `ViewerContent` (off the main actor).
nonisolated enum ViewerLoader {
    enum LoadError: LocalizedError {
        case empty, unsupported(String)
        var errorDescription: String? {
            switch self {
            case .empty: "Görüntülenecek geometri yok (tarama boş olabilir)."
            case .unsupported(let ext): "Bu dosya türü görüntülenemiyor: .\(ext)"
            }
        }
    }

    static func load(_ source: ViewerRequest.Source) async throws -> ViewerContent {
        switch source {
        case .meshChunks(let dir):
            let store = MeshStore()
            _ = try await store.load(from: dir)
            let mesh = MeshMerger.merge(await store.snapshot())
            guard mesh.triangleCount > 0 else { throw LoadError.empty }
            return .mesh(mesh)
        case .file(let url):
            switch url.pathExtension.lowercased() {
            case "ply":
                // App-written PLYs are millimetres, Y up.
                let m = try PLYBinaryReader().read(from: url, options: ExportOptions(unit: .millimeters, upAxis: .y))
                if m.triangleCount > 0 { return .mesh(m) }
                guard m.vertexCount > 0 else { throw LoadError.empty }
                return .points(m.positions)
            case "stl", "obj":
                let reader: any MeshReader = url.pathExtension.lowercased() == "stl" ? STLBinaryReader() : OBJReader()
                let m = try reader.read(from: url, options: ExportOptions(unit: .millimeters, upAxis: .z))
                guard m.triangleCount > 0 else { throw LoadError.empty }
                return .mesh(m)
            case "usdz", "usd", "usdc":
                return .scene(try SCNScene(url: url))
            default:
                throw LoadError.unsupported(url.pathExtension)
            }
        }
    }
}
