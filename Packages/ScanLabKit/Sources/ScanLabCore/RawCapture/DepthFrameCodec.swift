import Foundation
import simd

public enum DepthFrameCodecError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt16)
    case corrupt(String)
}

/// SLDF v1 (little-endian), shared with `scanlab-mac/scanlab/recon/capture.py`:
/// "SLDF" | u16 version | u16 reserved | u32 width | u32 height | f32 fx, fy, cx, cy |
/// f32[16] column-major pose | f64 timestamp | f32 depth[w·h] | u8 confidence[w·h]
public enum DepthFrameCodec {
    static let magic = Array("SLDF".utf8)
    static let version: UInt16 = 1
    static let headerSize = 4 + 2 + 2 + 4 + 4 + 16 + 64 + 8

    public static func encode(_ f: DepthFrame) -> Data {
        var w = ByteWriter(capacity: headerSize + f.depth.count * 5)
        w.write(bytes: magic)
        w.write(version)
        w.write(UInt16(0))
        w.write(UInt32(f.width))
        w.write(UInt32(f.height))
        w.write(f.fx); w.write(f.fy); w.write(f.cx); w.write(f.cy)
        for col in 0..<4 {
            let c = f.pose[col]
            w.write(c.x); w.write(c.y); w.write(c.z); w.write(c.w)
        }
        w.write(f.timestamp.bitPattern)
        for d in f.depth { w.write(d) }
        w.write(bytes: f.confidence)
        return w.data
    }

    public static func decode(_ data: Data) throws -> DepthFrame {
        var r = ByteReader(data)
        guard Array(try r.bytes(4)) == magic else { throw DepthFrameCodecError.badMagic }
        let v = try r.read(UInt16.self)
        guard v == version else { throw DepthFrameCodecError.unsupportedVersion(v) }
        _ = try r.read(UInt16.self)
        let width = Int(try r.read(UInt32.self)), height = Int(try r.read(UInt32.self))
        let fx = try r.readFloat(), fy = try r.readFloat(), cx = try r.readFloat(), cy = try r.readFloat()
        var cols: [SIMD4<Float>] = []
        for _ in 0..<4 { cols.append(SIMD4(try r.readFloat(), try r.readFloat(), try r.readFloat(), try r.readFloat())) }
        let timestamp = Double(bitPattern: try r.read(UInt64.self))
        let n = width * height
        guard r.remaining == n * 5 else { throw DepthFrameCodecError.corrupt("payload size mismatch") }
        var depth: [Float] = []
        depth.reserveCapacity(n)
        for _ in 0..<n { depth.append(try r.readFloat()) }
        let confidence = Array(try r.bytes(n))
        return DepthFrame(width: width, height: height, depth: depth, confidence: confidence, fx: fx, fy: fy, cx: cx, cy: cy,
                          pose: simd_float4x4(cols[0], cols[1], cols[2], cols[3]), timestamp: timestamp)
    }
}
