import ScanLabCore

enum ExportFixtures {
    /// Closed unit cube, 8 vertices, 12 triangles, outward winding.
    static var cube: TriangleMesh {
        let p: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1),
        ]
        let i: [UInt32] = [
            0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
            0, 1, 5, 0, 5, 4, 2, 3, 7, 2, 7, 6,
            1, 2, 6, 1, 6, 5, 0, 4, 7, 0, 7, 3,
        ]
        let colors = p.map { SIMD3<UInt8>(UInt8($0.x * 255), UInt8($0.y * 255), UInt8($0.z * 255)) }
        return TriangleMesh(positions: p.map { $0 * 0.3 }, indices: i, colors: colors)
    }
}
