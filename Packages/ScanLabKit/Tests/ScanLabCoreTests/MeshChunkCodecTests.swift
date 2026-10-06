import Foundation
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
