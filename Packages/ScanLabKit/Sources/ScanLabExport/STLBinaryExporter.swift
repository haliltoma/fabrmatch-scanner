import Foundation
import ScanLabCore
import simd

/// Binary STL: 80-byte header, u32 triangle count, then per triangle 12×f32 (normal + 3 vertices) + u16 attribute.
public struct STLBinaryExporter: MeshExporter {
    public init() {}

    public func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws {
        var out = try StreamingFileWriter(url: url)
        do {
            var header = Array("ScanLab STL".utf8)
            header += [UInt8](repeating: 0x20, count: 80 - header.count)
            var w = ByteWriter(capacity: 1 << 20)
            w.write(bytes: header)
            w.write(UInt32(mesh.triangleCount))
            for t in 0..<mesh.triangleCount {
                let (a, b, c) = mesh.triangle(t)
                let ta = options.transform(a), tb = options.transform(b), tc = options.transform(c)
                let n = safeNormalize(simd_cross(tb - ta, tc - ta))
                w.write(n); w.write(ta); w.write(tb); w.write(tc)
                w.write(UInt16(0))
                if w.data.count >= 1 << 20 {
                    try out.write(w.data)
                    w.removeAll()
                }
            }
            try out.write(w.data)
            try out.finish()
        } catch {
            out.abandon()
            throw error
        }
    }
}

func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = simd_length(v)
    return len > 0 ? v / len : .zero
}
