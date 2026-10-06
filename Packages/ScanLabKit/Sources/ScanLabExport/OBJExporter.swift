import Foundation
import ScanLabCore

/// Wavefront OBJ (positions + faces), streamed line by line. Textures/MTL arrive with M8.
public struct OBJExporter: MeshExporter {
    public init() {}

    public func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws {
        var out = try StreamingFileWriter(url: url)
        do {
            try out.write("# ScanLab export\n# unit: \(options.unit.symbol), up: \(options.upAxis.rawValue)\n")
            try out.write("# vertices: \(mesh.vertexCount) triangles: \(mesh.triangleCount)\n")
            var line = ""
            line.reserveCapacity(1 << 20)
            for p in mesh.positions {
                let q = options.transform(p)
                line += "v \(q.x) \(q.y) \(q.z)\n"
                if line.utf8.count >= 1 << 20 { try out.write(line); line.removeAll(keepingCapacity: true) }
            }
            for t in 0..<mesh.triangleCount {
                line += "f \(mesh.indices[3 * t] + 1) \(mesh.indices[3 * t + 1] + 1) \(mesh.indices[3 * t + 2] + 1)\n"
                if line.utf8.count >= 1 << 20 { try out.write(line); line.removeAll(keepingCapacity: true) }
            }
            try out.write(line)
            try out.finish()
        } catch {
            out.abandon()
            throw error
        }
    }
}
