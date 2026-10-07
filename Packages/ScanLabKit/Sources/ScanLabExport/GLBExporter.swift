import Foundation
import ScanLabCore
import simd

/// Binary glTF 2.0 (M13): 12-byte header, JSON chunk, BIN chunk (each 4-byte aligned).
/// glTF is metres and Y-up by definition, so `options.unit`/`upAxis` only apply when explicitly
/// set otherwise (they are honoured for symmetry with the other exporters).
public struct GLBExporter: MeshExporter {
    public init() {}

    public func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws {
        let positions = mesh.positions.map(options.transform)
        var bin = ByteWriter(capacity: positions.count * 12 + mesh.indices.count * 4)
        for p in positions { bin.write(p) }
        let indexOffset = bin.data.count
        for i in mesh.indices { bin.write(i) }
        let lo = positions.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let hi = positions.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        let hasFaces = !mesh.indices.isEmpty

        var accessors: [[String: Any]] = [[
            "bufferView": 0, "componentType": 5126, "count": positions.count, "type": "VEC3",
            "min": positions.isEmpty ? [0, 0, 0] : [lo.x, lo.y, lo.z], "max": positions.isEmpty ? [0, 0, 0] : [hi.x, hi.y, hi.z],
        ]]
        var views: [[String: Any]] = [["buffer": 0, "byteOffset": 0, "byteLength": indexOffset, "target": 34962]]
        var primitive: [String: Any] = ["attributes": ["POSITION": 0], "mode": hasFaces ? 4 : 0]
        if hasFaces {
            views.append(["buffer": 0, "byteOffset": indexOffset, "byteLength": mesh.indices.count * 4, "target": 34963])
            accessors.append(["bufferView": 1, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])
            primitive["indices"] = 1
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "ScanLab"],
            "scene": 0, "scenes": [["nodes": [0]]], "nodes": [["mesh": 0]],
            "meshes": [["primitives": [primitive]]],
            "buffers": [["byteLength": bin.data.count]], "bufferViews": views, "accessors": accessors,
        ]
        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }
        var binData = bin.data
        while binData.count % 4 != 0 { binData.append(0) }

        var out = ByteWriter(capacity: 28 + jsonData.count + binData.count)
        out.write(bytes: Array("glTF".utf8))
        out.write(UInt32(2))
        out.write(UInt32(12 + 8 + jsonData.count + 8 + binData.count))
        out.write(UInt32(jsonData.count)); out.write(bytes: Array("JSON".utf8)); out.write(bytes: jsonData)
        out.write(UInt32(binData.count)); out.write(bytes: Array("BIN\0".utf8)); out.write(bytes: binData)
        try out.data.write(to: url, options: .atomic)
    }
}

/// Reads the GLB subset `GLBExporter` writes (one mesh, POSITION + optional uint32 indices).
public struct GLBReader: MeshReader {
    public init() {}

    public func read(from url: URL, options: ExportOptions) throws -> TriangleMesh {
        let data = try Data(contentsOf: url)
        var r = ByteReader(data)
        guard Array(try r.bytes(4)) == Array("glTF".utf8), try r.read(UInt32.self) == 2 else {
            throw MeshFormatError.invalidHeader("not a glTF 2.0 binary")
        }
        _ = try r.read(UInt32.self)
        let jsonLength = Int(try r.read(UInt32.self))
        guard Array(try r.bytes(4)) == Array("JSON".utf8) else { throw MeshFormatError.invalidHeader("missing JSON chunk") }
        let json = try JSONSerialization.jsonObject(with: try r.bytes(jsonLength)) as? [String: Any] ?? [:]
        let binLength = Int(try r.read(UInt32.self))
        _ = try r.bytes(4)
        let bin = try r.bytes(binLength)
        guard let accessors = json["accessors"] as? [[String: Any]], let views = json["bufferViews"] as? [[String: Any]],
              let count = accessors.first?["count"] as? Int else { throw MeshFormatError.invalidHeader("no accessors") }
        var pr = ByteReader(bin, offset: (views[0]["byteOffset"] as? Int) ?? 0)
        var positions: [SIMD3<Float>] = []
        for _ in 0..<count { positions.append(options.inverseTransform(try pr.readVector())) }
        var indices: [UInt32] = []
        if accessors.count > 1, views.count > 1, let n = accessors[1]["count"] as? Int {
            var ir = ByteReader(bin, offset: (views[1]["byteOffset"] as? Int) ?? 0)
            for _ in 0..<n { indices.append(try ir.read(UInt32.self)) }
        }
        return TriangleMesh(positions: positions, indices: indices)
    }
}
