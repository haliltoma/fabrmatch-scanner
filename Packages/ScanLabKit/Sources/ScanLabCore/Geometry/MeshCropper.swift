import simd

/// Box crop (FR-9.9): keeps triangles whose centroid lies inside `box`, drops unused vertices and
/// re-indexes. Per-face classifications and per-vertex colours follow their triangles/vertices.
public enum MeshCropper {
    public static func crop(_ mesh: TriangleMesh, to box: BoundingBox) -> TriangleMesh {
        guard mesh.triangleCount > 0 else { return cropPoints(mesh, to: box) }
        let hasClasses = mesh.faceClassifications.count == mesh.triangleCount
        let hasColors = mesh.colors.count == mesh.vertexCount
        var remap = [Int32](repeating: -1, count: mesh.vertexCount)
        var positions: [SIMD3<Float>] = [], colors: [SIMD3<UInt8>] = [], indices: [UInt32] = [], classes: [UInt8] = []
        for t in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(t)
            guard contains(box, (a + b + c) / 3) else { continue }
            for k in 0..<3 {
                let old = Int(mesh.indices[3 * t + k])
                if remap[old] < 0 {
                    remap[old] = Int32(positions.count)
                    positions.append(mesh.positions[old])
                    if hasColors { colors.append(mesh.colors[old]) }
                }
                indices.append(UInt32(remap[old]))
            }
            if hasClasses { classes.append(mesh.faceClassifications[t]) }
        }
        return TriangleMesh(positions: positions, indices: indices, colors: colors, faceClassifications: classes)
    }

    static func cropPoints(_ mesh: TriangleMesh, to box: BoundingBox) -> TriangleMesh {
        let keep = mesh.positions.indices.filter { contains(box, mesh.positions[$0]) }
        let colors = mesh.colors.count == mesh.vertexCount ? keep.map { mesh.colors[$0] } : []
        return TriangleMesh(positions: keep.map { mesh.positions[$0] }, colors: colors)
    }

    /// The sub-box selected by per-axis fractions (0…1) of `bounds` — what the crop sliders control.
    public static func box(in bounds: BoundingBox, lower: SIMD3<Float>, upper: SIMD3<Float>) -> BoundingBox {
        let lo = simd_min(lower, upper), hi = simd_max(lower, upper)
        return BoundingBox(min: bounds.min + bounds.size * lo, max: bounds.min + bounds.size * hi)
    }

    static func contains(_ box: BoundingBox, _ p: SIMD3<Float>) -> Bool {
        all(p .>= box.min) && all(p .<= box.max)
    }
}
