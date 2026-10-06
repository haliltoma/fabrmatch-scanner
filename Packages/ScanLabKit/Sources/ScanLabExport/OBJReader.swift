import Foundation
import ScanLabCore

/// Minimal OBJ reader: `v` and triangular/polygonal `f` records (fans polygons), ignores the rest.
public struct OBJReader: MeshReader {
    public init() {}

    public func read(from url: URL, options: ExportOptions) throws -> TriangleMesh {
        let text = try String(contentsOf: url, encoding: .utf8)
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let parts = raw.split(separator: " ", omittingEmptySubsequences: true)
            guard let tag = parts.first else { continue }
            switch tag {
            case "v":
                guard parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) else {
                    throw MeshFormatError.invalidHeader("bad vertex: \(raw)")
                }
                positions.append(options.inverseTransform(SIMD3(x, y, z)))
            case "f":
                let refs = try parts.dropFirst().map { token -> UInt32 in
                    guard let first = token.split(separator: "/").first, let i = Int(first) else {
                        throw MeshFormatError.invalidHeader("bad face: \(raw)")
                    }
                    let resolved = i < 0 ? positions.count + i : i - 1
                    guard resolved >= 0, resolved < positions.count else { throw MeshFormatError.invalidHeader("face index out of range") }
                    return UInt32(resolved)
                }
                guard refs.count >= 3 else { throw MeshFormatError.invalidHeader("face with < 3 vertices") }
                for k in 1..<refs.count - 1 { indices += [refs[0], refs[k], refs[k + 1]] }
            default:
                continue
            }
        }
        return TriangleMesh(positions: positions, indices: indices)
    }
}
