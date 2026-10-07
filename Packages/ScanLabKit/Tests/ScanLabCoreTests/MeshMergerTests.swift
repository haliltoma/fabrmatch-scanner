import simd
import Testing
@testable import ScanLabCore

@Suite struct MeshMergerTests {
    @Test("Adjacent anchors share an edge after welding")
    func weldsSharedEdge() {
        let left = MeshFixtures.floorQuad()
        // Second quad offset by 1 m + 2 mm jitter: its left edge coincides with the first quad's right edge.
        let right = MeshFixtures.floorQuad(offset: SIMD3(1.002, 0, 0))
        let mesh = MeshMerger.merge([left, right], weldTolerance: 0.005)
        #expect(mesh.triangleCount == 4)
        #expect(mesh.vertexCount == 6)
        #expect(mesh.faceClassifications == [2, 2, 2, 2])
        let bounds = mesh.bounds
        #expect(bounds?.isApproximatelyEqual(to: BoundingBox(min: .zero, max: SIMD3(2.002, 0, 1)), tolerance: 1e-5) == true)
    }

    @Test("Vertices farther apart than the tolerance stay separate")
    func respectsTolerance() {
        let mesh = MeshMerger.merge([MeshFixtures.floorQuad(), MeshFixtures.floorQuad(offset: SIMD3(1.01, 0, 0))], weldTolerance: 0.005)
        #expect(mesh.vertexCount == 8)
    }

    @Test("Triangles collapsed by welding or with zero area are dropped")
    func dropsDegenerates() {
        let chunk = MeshChunk(
            id: .init(), version: 1, transform: matrix_identity_float4x4,
            vertices: [SIMD3(0, 0, 0), SIMD3(0.001, 0, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(2, 0, 0)],
            indices: [0, 1, 2, /* collapses */ 0, 3, 4 /* collinear */, 0, 2, 3 /* valid */]
        )
        let mesh = MeshMerger.merge([chunk], weldTolerance: 0.005)
        #expect(mesh.triangleCount == 1)
        #expect(mesh.faceClassifications.isEmpty)
    }

    @Test func appliesAnchorTransform() {
        let mesh = MeshMerger.merge([MeshFixtures.floorQuad(offset: SIMD3(0, 2, 0))])
        #expect(mesh.positions.allSatisfy { $0.y == 2 })
    }
}

@Suite struct RangeFilterTests {
    @Test("FR-3.5 removes geometry beyond the max range")
    func dropsFarTriangles() {
        let near = MeshFixtures.floorQuad()
        let far = MeshFixtures.floorQuad(offset: SIMD3(10, 0, 0))
        #expect(near.filtered(maxDistance: 2, from: .zero).triangleCount == 2)
        let filtered = far.filtered(maxDistance: 2, from: .zero)
        #expect(filtered.triangleCount == 0)
        #expect(filtered.classifications.isEmpty)
        #expect(filtered.vertices.count == 4)
    }
}

@Suite struct MeshCropperTests {
    @Test("Cropping keeps triangles inside the box, re-indexes and carries classes")
    func cropsMesh() {
        let left = MeshFixtures.floorQuad()
        let right = MeshFixtures.floorQuad(offset: SIMD3(5, 0, 0))
        let mesh = MeshMerger.merge([left, right])
        let cropped = MeshCropper.crop(mesh, to: BoundingBox(min: SIMD3(-0.1, -1, -0.1), max: SIMD3(1.1, 1, 1.1)))
        #expect(cropped.triangleCount == 2 && cropped.vertexCount == 4)
        #expect(cropped.faceClassifications == [2, 2])
        #expect(cropped.indices.allSatisfy { Int($0) < cropped.vertexCount })
        #expect(cropped.bounds?.max.x ?? 9 <= 1.0001)
    }

    @Test func cropsPointClouds() {
        let cloud = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0.5, 0.5, 0.5)])
        let cropped = MeshCropper.crop(cloud, to: BoundingBox(min: .zero, max: SIMD3(1, 1, 1)))
        #expect(cropped.vertexCount == 2)
    }

    @Test("Slider fractions map onto the bounds; swapped handles still give a valid box")
    func fractionsToBox() {
        let b = BoundingBox(min: SIMD3(0, 0, 0), max: SIMD3(10, 20, 30))
        let box = MeshCropper.box(in: b, lower: SIMD3(0.1, 0.5, 1), upper: SIMD3(0.9, 1, 0))
        #expect(box.min == SIMD3(1, 10, 0) && box.max == SIMD3(9, 20, 30))
    }
}
