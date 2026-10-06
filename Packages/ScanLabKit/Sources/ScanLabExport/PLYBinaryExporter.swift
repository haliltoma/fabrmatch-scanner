import Foundation
import ScanLabCore

/// Binary little-endian PLY with optional per-vertex RGB (M13 format notes).
public struct PLYBinaryExporter: MeshExporter {
    public init() {}

    public func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws {
        let colors = options.includeColors && mesh.colors.count == mesh.vertexCount && mesh.vertexCount > 0
        var header = "ply\nformat binary_little_endian 1.0\ncomment ScanLab export, unit=\(options.unit.symbol)\n"
        header += "element vertex \(mesh.vertexCount)\nproperty float x\nproperty float y\nproperty float z\n"
        if colors { header += "property uchar red\nproperty uchar green\nproperty uchar blue\n" }
        header += "element face \(mesh.triangleCount)\nproperty list uchar uint vertex_indices\nend_header\n"

        var out = try StreamingFileWriter(url: url)
        do {
            try out.write(header)
            var w = ByteWriter(capacity: 1 << 20)
            for i in 0..<mesh.vertexCount {
                w.write(options.transform(mesh.positions[i]))
                if colors { let c = mesh.colors[i]; w.write(c.x); w.write(c.y); w.write(c.z) }
                if w.data.count >= 1 << 20 { try out.write(w.data); w.removeAll() }
            }
            for t in 0..<mesh.triangleCount {
                w.write(UInt8(3))
                w.write(mesh.indices[3 * t]); w.write(mesh.indices[3 * t + 1]); w.write(mesh.indices[3 * t + 2])
                if w.data.count >= 1 << 20 { try out.write(w.data); w.removeAll() }
            }
            try out.write(w.data)
            try out.finish()
        } catch {
            out.abandon()
            throw error
        }
    }
}
