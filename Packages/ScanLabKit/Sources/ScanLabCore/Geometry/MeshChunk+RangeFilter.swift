import simd

extension MeshChunk {
    /// FR-3.5: drops triangles whose world-space centroid is farther than `maxDistance`
    /// from `cameraPosition`. Vertices are kept so indices stay valid; unused ones are harmless
    /// and disappear at export after merging.
    public func filtered(maxDistance: Float, from cameraPosition: SIMD3<Float>) -> MeshChunk {
        let world = worldVertices()
        let limit = maxDistance * maxDistance
        var kept: [UInt32] = []
        var keptClasses: [UInt8] = []
        let hasClasses = classifications.count == triangleCount
        kept.reserveCapacity(indices.count)
        for t in 0..<triangleCount {
            let a = indices[3 * t], b = indices[3 * t + 1], c = indices[3 * t + 2]
            let centroid = (world[Int(a)] + world[Int(b)] + world[Int(c)]) / 3
            guard simd_distance_squared(centroid, cameraPosition) <= limit else { continue }
            kept += [a, b, c]
            if hasClasses { keptClasses.append(classifications[t]) }
        }
        var copy = self
        copy.indices = kept
        copy.classifications = keptClasses
        return copy
    }
}
