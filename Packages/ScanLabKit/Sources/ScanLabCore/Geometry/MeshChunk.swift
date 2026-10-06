import Foundation
import simd

/// One `ARMeshAnchor` worth of geometry, copied out of ARKit into a plain value (PRD §4.5).
/// Vertices stay in anchor-local space; `transform` maps them to world space.
public struct MeshChunk: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Monotonic per-chunk revision so stale updates never overwrite newer ones (M23 note).
    public var version: UInt64
    public var transform: simd_float4x4
    public var vertices: [SIMD3<Float>]
    public var indices: [UInt32]
    /// Per-face classification bytes; empty when classification is off.
    public var classifications: [UInt8]

    public init(id: UUID, version: UInt64, transform: simd_float4x4, vertices: [SIMD3<Float>], indices: [UInt32], classifications: [UInt8] = []) {
        self.id = id
        self.version = version
        self.transform = transform
        self.vertices = vertices
        self.indices = indices
        self.classifications = classifications
    }

    public var triangleCount: Int { indices.count / 3 }

    public func worldVertices() -> [SIMD3<Float>] {
        vertices.map { v in
            let w = transform * SIMD4<Float>(v, 1)
            return SIMD3<Float>(w.x, w.y, w.z)
        }
    }
}
