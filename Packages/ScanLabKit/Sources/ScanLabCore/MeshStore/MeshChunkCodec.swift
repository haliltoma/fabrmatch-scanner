import Foundation
import simd

public enum MeshChunkCodecError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt16)
    case corrupt(String)
}

/// Binary layout of `raw/mesh_chunks/<uuid>.bin` (little-endian):
/// "SLMC" | u16 format | u16 reserved | uuid[16] | u64 version | f32[16] column-major transform |
/// u32 vertexCount | u32 indexCount | u32 classCount | f32[3·v] | u32[i] | u8[c]
public enum MeshChunkCodec {
    static let magic: [UInt8] = Array("SLMC".utf8)
    static let formatVersion: UInt16 = 1

    public static func encode(_ chunk: MeshChunk) -> Data {
        var w = ByteWriter(capacity: 128 + chunk.vertices.count * 12 + chunk.indices.count * 4 + chunk.classifications.count)
        w.write(bytes: magic)
        w.write(formatVersion)
        w.write(UInt16(0))
        w.write(chunk.id)
        w.write(chunk.version)
        for col in 0..<4 {
            let c = chunk.transform[col]
            w.write(c.x); w.write(c.y); w.write(c.z); w.write(c.w)
        }
        w.write(UInt32(chunk.vertices.count))
        w.write(UInt32(chunk.indices.count))
        w.write(UInt32(chunk.classifications.count))
        for v in chunk.vertices { w.write(v) }
        for i in chunk.indices { w.write(i) }
        w.write(bytes: chunk.classifications)
        return w.data
    }

    public static func decode(_ data: Data) throws -> MeshChunk {
        var r = ByteReader(data)
        guard Array(try r.bytes(4)) == magic else { throw MeshChunkCodecError.badMagic }
        let format = try r.read(UInt16.self)
        guard format == formatVersion else { throw MeshChunkCodecError.unsupportedVersion(format) }
        _ = try r.read(UInt16.self)
        let id = try r.readUUID()
        let version = try r.read(UInt64.self)
        var columns: [SIMD4<Float>] = []
        for _ in 0..<4 {
            columns.append(SIMD4(try r.readFloat(), try r.readFloat(), try r.readFloat(), try r.readFloat()))
        }
        let vertexCount = Int(try r.read(UInt32.self))
        let indexCount = Int(try r.read(UInt32.self))
        let classCount = Int(try r.read(UInt32.self))
        guard indexCount % 3 == 0 else { throw MeshChunkCodecError.corrupt("index count \(indexCount) not a multiple of 3") }
        guard r.remaining == vertexCount * 12 + indexCount * 4 + classCount else {
            throw MeshChunkCodecError.corrupt("payload size mismatch")
        }
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount { vertices.append(try r.readVector()) }
        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        for _ in 0..<indexCount {
            let i = try r.read(UInt32.self)
            guard i < vertexCount else { throw MeshChunkCodecError.corrupt("index \(i) out of range") }
            indices.append(i)
        }
        let classifications = Array(try r.bytes(classCount))
        return MeshChunk(
            id: id, version: version,
            transform: simd_float4x4(columns[0], columns[1], columns[2], columns[3]),
            vertices: vertices, indices: indices, classifications: classifications
        )
    }
}
