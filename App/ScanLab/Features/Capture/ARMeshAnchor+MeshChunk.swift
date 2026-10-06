import ARKit
import ScanLabCore

extension ARMeshAnchor {
    /// Copies the anchor's GPU buffers into a plain `MeshChunk` value (PRD §4.5 step 2).
    /// Vertices stay anchor-local; `transform` maps to world space.
    nonisolated func makeChunk(version: UInt64) -> MeshChunk {
        let g = geometry

        let vs = g.vertices
        let vBase = vs.buffer.contents().advanced(by: vs.offset)
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vs.count)
        for i in 0..<vs.count {
            let p = vBase.advanced(by: i * vs.stride).assumingMemoryBound(to: Float.self)
            vertices.append(SIMD3(p[0], p[1], p[2]))
        }

        let faces = g.faces
        let indexCount = faces.count * faces.indexCountPerPrimitive
        let fBase = faces.buffer.contents()
        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        if faces.bytesPerIndex == 4 {
            let p = fBase.assumingMemoryBound(to: UInt32.self)
            for i in 0..<indexCount { indices.append(p[i]) }
        } else {
            let p = fBase.assumingMemoryBound(to: UInt16.self)
            for i in 0..<indexCount { indices.append(UInt32(p[i])) }
        }

        var classes: [UInt8] = []
        if let c = g.classification {
            classes.reserveCapacity(c.count)
            let cBase = c.buffer.contents().advanced(by: c.offset)
            for i in 0..<c.count { classes.append(cBase.advanced(by: i * c.stride).load(as: UInt8.self)) }
        }

        return MeshChunk(id: identifier, version: version, transform: transform, vertices: vertices, indices: indices, classifications: classes)
    }
}
