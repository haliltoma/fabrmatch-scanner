import ScanLabCore
import SceneKit

/// Loaded geometry, ready for SceneKit. Built off the main actor.
nonisolated enum ViewerContent: @unchecked Sendable {
    /// Triangle mesh in meters, Y up (ARKit world), optional per-face ARKit classification.
    case mesh(TriangleMesh)
    /// Points in meters, Y up.
    case points([SIMD3<Float>])
    /// A complete scene (USDZ etc.). SCNScene is not Sendable; it is created on the loader's task and
    /// only handed to the main actor afterwards, never shared.
    case scene(SCNScene)

    var summary: (vertices: Int, triangles: Int, size: SIMD3<Float>?) {
        switch self {
        case .mesh(let m): return (m.vertexCount, m.triangleCount, m.bounds?.size)
        case .points(let p): return (p.count, 0, BoundingBox(points: p)?.size)
        case .scene(let s):
            let (lo, hi) = s.rootNode.boundingBox
            return (0, 0, SIMD3(Float(hi.x - lo.x), Float(hi.y - lo.y), Float(hi.z - lo.z)))
        }
    }
}
