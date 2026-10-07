import Foundation
import ScanLabCore

/// Plain-text point list, one "x y z" per line (FR-4.7). Faces are ignored.
public struct XYZExporter: MeshExporter {
    public init() {}

    public func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws {
        var out = try StreamingFileWriter(url: url)
        do {
            var text = ""
            text.reserveCapacity(1 << 20)
            for p in mesh.positions {
                let q = options.transform(p)
                text += "\(q.x) \(q.y) \(q.z)\n"
                if text.utf8.count >= 1 << 20 { try out.write(text); text.removeAll(keepingCapacity: true) }
            }
            try out.write(text)
            try out.finish()
        } catch {
            out.abandon()
            throw error
        }
    }
}

public struct XYZReader: MeshReader {
    public init() {}

    public func read(from url: URL, options: ExportOptions) throws -> TriangleMesh {
        let text = try String(contentsOf: url, encoding: .utf8)
        var points: [SIMD3<Float>] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let v = line.split(separator: " ").compactMap { Float($0) }
            guard v.count >= 3 else { throw MeshFormatError.invalidHeader("bad line: \(line)") }
            points.append(options.inverseTransform(SIMD3(v[0], v[1], v[2])))
        }
        return TriangleMesh(positions: points)
    }
}
