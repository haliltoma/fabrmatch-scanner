import Foundation
import simd
import Testing
@testable import ScanLabCore

@Suite struct MeshChunkCodecTests {
    @Test func roundTripIsLossless() throws {
        let chunk = MeshFixtures.floorQuad(version: 42, offset: SIMD3(1.5, -0.25, 3))
        #expect(try MeshChunkCodec.decode(MeshChunkCodec.encode(chunk)) == chunk)
    }

    @Test("Truncated files throw instead of crashing", arguments: [0, 3, 10, 60, 100])
    func truncated(length: Int) {
        let data = MeshChunkCodec.encode(MeshFixtures.floorQuad())
        #expect(throws: (any Error).self) { try MeshChunkCodec.decode(data.prefix(length)) }
    }

    @Test func rejectsBadMagic() {
        var data = MeshChunkCodec.encode(MeshFixtures.floorQuad())
        data[0] = 0x00
        #expect(throws: MeshChunkCodecError.badMagic) { try MeshChunkCodec.decode(data) }
    }

    @Test func rejectsOutOfRangeIndex() {
        var chunk = MeshFixtures.floorQuad()
        chunk.indices[0] = 99
        #expect(throws: MeshChunkCodecError.self) { try MeshChunkCodec.decode(MeshChunkCodec.encode(chunk)) }
    }
}

@Suite("Cross-language golden file")
struct MeshChunkGoldenTests {
    static let golden = URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../fixtures/chunk_v1.bin").standardized

    @Test("Swift encoder matches fixtures/chunk_v1.bin byte for byte")
    func encoderMatchesGolden() throws {
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(1, 2, 3, 1)
        let chunk = MeshChunk(
            id: try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")), version: 7, transform: t,
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 0, 1), SIMD3(0, 0, 1)],
            indices: [0, 2, 1, 0, 3, 2], classifications: [2, 2]
        )
        #expect(MeshChunkCodec.encode(chunk) == (try Data(contentsOf: Self.golden)))
    }
}
