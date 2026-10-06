import simd

/// Indexed triangle mesh in world space, meters. Structure-of-arrays layout (M9 technical note).
public struct TriangleMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    /// Three indices per triangle.
    public var indices: [UInt32]
    /// Optional per-vertex RGB; empty or `positions.count` long.
    public var colors: [SIMD3<UInt8>]
    /// Optional per-face ARKit classification; empty or `triangleCount` long.
    public var faceClassifications: [UInt8]

    public init(positions: [SIMD3<Float>] = [], indices: [UInt32] = [], colors: [SIMD3<UInt8>] = [], faceClassifications: [UInt8] = []) {
        precondition(indices.count % 3 == 0, "indices must describe whole triangles")
        self.positions = positions
        self.indices = indices
        self.colors = colors
        self.faceClassifications = faceClassifications
    }

    public var triangleCount: Int { indices.count / 3 }
    public var vertexCount: Int { positions.count }
    public var bounds: BoundingBox? { BoundingBox(points: positions) }
    public var hasColors: Bool { !colors.isEmpty }

    public func triangle(_ i: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (positions[Int(indices[3 * i])], positions[Int(indices[3 * i + 1])], positions[Int(indices[3 * i + 2])])
    }

    /// Unit normal by right-hand winding; zero vector for degenerate triangles.
    public func faceNormal(_ i: Int) -> SIMD3<Float> {
        let (a, b, c) = triangle(i)
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        return len > 0 ? n / len : .zero
    }
}
