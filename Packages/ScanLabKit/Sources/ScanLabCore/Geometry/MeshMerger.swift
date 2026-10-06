import simd

/// Merges anchor chunks into one world-space mesh (PRD §4.5 step 4, M3 technical note).
///
/// Overlapping anchors produce near-duplicate vertices; they are welded within `weldTolerance`
/// (default 5 mm) using a spatial hash, then degenerate triangles are dropped.
public enum MeshMerger {
    public static func merge(_ chunks: [MeshChunk], weldTolerance: Float = 0.005) -> TriangleMesh {
        var welder = VertexWelder(tolerance: weldTolerance)
        var indices: [UInt32] = []
        var classes: [UInt8] = []
        let keepClasses = !chunks.isEmpty && chunks.allSatisfy { $0.classifications.count == $0.triangleCount }
        indices.reserveCapacity(chunks.reduce(0) { $0 + $1.indices.count })

        for chunk in chunks {
            let remap = chunk.worldVertices().map { welder.index(for: $0) }
            for t in 0..<chunk.triangleCount {
                let a = remap[Int(chunk.indices[3 * t])]
                let b = remap[Int(chunk.indices[3 * t + 1])]
                let c = remap[Int(chunk.indices[3 * t + 2])]
                guard a != b, b != c, a != c else { continue }
                indices += [a, b, c]
                if keepClasses { classes.append(chunk.classifications[t]) }
            }
        }
        var mesh = TriangleMesh(positions: welder.positions, indices: indices, faceClassifications: classes)
        removeZeroAreaTriangles(&mesh)
        return mesh
    }

    /// Drops triangles whose area is below `epsilon` (m²); unused vertices are kept.
    static func removeZeroAreaTriangles(_ mesh: inout TriangleMesh, epsilon: Float = 1e-12) {
        var kept: [UInt32] = []
        var keptClasses: [UInt8] = []
        kept.reserveCapacity(mesh.indices.count)
        let hasClasses = mesh.faceClassifications.count == mesh.triangleCount
        for t in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(t)
            guard simd_length_squared(simd_cross(b - a, c - a)) * 0.25 > epsilon * epsilon else { continue }
            kept += mesh.indices[3 * t..<3 * t + 3]
            if hasClasses { keptClasses.append(mesh.faceClassifications[t]) }
        }
        mesh.indices = kept
        mesh.faceClassifications = keptClasses
    }
}

/// Spatial-hash vertex deduplication: a vertex reuses an existing one within `tolerance`.
struct VertexWelder {
    let tolerance: Float
    private(set) var positions: [SIMD3<Float>] = []
    private var grid: [SIMD3<Int32>: [UInt32]] = [:]

    init(tolerance: Float) {
        precondition(tolerance > 0)
        self.tolerance = tolerance
    }

    mutating func index(for p: SIMD3<Float>) -> UInt32 {
        let cell = SIMD3<Int32>((p / tolerance).rounded(.down))
        let tol2 = tolerance * tolerance
        for dx: Int32 in -1...1 {
            for dy: Int32 in -1...1 {
                for dz: Int32 in -1...1 {
                    guard let bucket = grid[cell &+ SIMD3(dx, dy, dz)] else { continue }
                    for i in bucket where simd_distance_squared(positions[Int(i)], p) <= tol2 {
                        return i
                    }
                }
            }
        }
        let i = UInt32(positions.count)
        positions.append(p)
        grid[cell, default: []].append(i)
        return i
    }
}
