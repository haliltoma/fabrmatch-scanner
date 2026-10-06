import Foundation
import simd
@testable import ScanLabCore

enum MeshFixtures {
    /// Unit square in the XZ plane (floor), two triangles, anchor-local.
    static func floorQuad(id: UUID = UUID(), version: UInt64 = 1, offset: SIMD3<Float> = .zero) -> MeshChunk {
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(offset, 1)
        return MeshChunk(
            id: id, version: version, transform: t,
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1), SIMD3(0, 0, 1)],
            indices: [0, 2, 1, 0, 3, 2],
            classifications: [2, 2]
        )
    }
}
