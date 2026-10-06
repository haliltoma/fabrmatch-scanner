import Foundation
import ScanLabCore

/// Reads the PLY subset written by `PLYBinaryExporter` (xyz float, optional uchar rgb, uchar/uint face list).
public struct PLYBinaryReader: MeshReader {
    public init() {}

    public func read(from url: URL, options: ExportOptions) throws -> TriangleMesh {
        let data = try Data(contentsOf: url)
        guard let end = data.range(of: Data("end_header\n".utf8)) else { throw MeshFormatError.invalidHeader("missing end_header") }
        let header = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = header.split(separator: "\n").map(String.init)
        guard lines.first == "ply", lines.contains("format binary_little_endian 1.0") else {
            throw MeshFormatError.unsupported("only binary_little_endian PLY")
        }
        func count(of element: String) -> Int? {
            lines.first { $0.hasPrefix("element \(element) ") }.flatMap { Int($0.split(separator: " ")[2]) }
        }
        guard let vertexCount = count(of: "vertex"), let faceCount = count(of: "face") else {
            throw MeshFormatError.invalidHeader("missing element counts")
        }
        let hasColor = lines.contains("property uchar red")

        var r = ByteReader(data, offset: end.upperBound - data.startIndex)
        var positions: [SIMD3<Float>] = [], colors: [SIMD3<UInt8>] = []
        positions.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            positions.append(options.inverseTransform(try r.readVector()))
            if hasColor { colors.append(SIMD3(try r.read(UInt8.self), try r.read(UInt8.self), try r.read(UInt8.self))) }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(faceCount * 3)
        for _ in 0..<faceCount {
            guard try r.read(UInt8.self) == 3 else { throw MeshFormatError.unsupported("non-triangle face") }
            for _ in 0..<3 {
                let i = try r.read(UInt32.self)
                guard i < vertexCount else { throw MeshFormatError.invalidHeader("index out of range") }
                indices.append(i)
            }
        }
        return TriangleMesh(positions: positions, indices: indices, colors: colors)
    }
}
