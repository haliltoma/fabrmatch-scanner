import Foundation
import ScanLabCore

/// Reads binary STL into an unwelded triangle soup (3 vertices per triangle).
public struct STLBinaryReader: MeshReader {
    public init() {}

    public func read(from url: URL, options: ExportOptions) throws -> TriangleMesh {
        let data = try Data(contentsOf: url)
        var r = ByteReader(data, offset: 80)
        guard data.count >= 84 else { throw MeshFormatError.truncated }
        let count = Int(try r.read(UInt32.self))
        guard r.remaining == count * 50 else { throw MeshFormatError.invalidHeader("expected \(count) triangles") }
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(count * 3)
        for _ in 0..<count {
            _ = try r.readVector()
            for _ in 0..<3 { positions.append(options.inverseTransform(try r.readVector())) }
            _ = try r.read(UInt16.self)
        }
        return TriangleMesh(positions: positions, indices: (0..<UInt32(positions.count)).map { $0 })
    }
}
