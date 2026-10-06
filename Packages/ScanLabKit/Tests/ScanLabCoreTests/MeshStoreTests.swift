import Foundation
import Testing
@testable import ScanLabCore

@Suite struct MeshStoreTests {
    @Test("Stale chunk versions never overwrite newer ones")
    func ignoresStaleVersions() async {
        let store = MeshStore()
        let id = UUID()
        #expect(await store.upsert(MeshFixtures.floorQuad(id: id, version: 2)))
        #expect(await store.upsert(MeshFixtures.floorQuad(id: id, version: 1, offset: SIMD3(9, 9, 9))) == false)
        #expect(await store.snapshot().first?.version == 2)
    }

    @Test func removeAndStats() async {
        let store = MeshStore()
        let a = MeshFixtures.floorQuad(), b = MeshFixtures.floorQuad()
        await store.upsert(a)
        await store.upsert(b)
        #expect(await store.stats == MeshStoreStats(chunkCount: 2, vertexCount: 8, triangleCount: 4))
        await store.remove(ids: [a.id])
        #expect(await store.stats.chunkCount == 1)
    }

    @Test("Autosave writes only dirty chunks, deletes removed ones, and restores")
    func flushAndLoad() async throws {
        let tmp = try TemporaryDirectory()
        let store = MeshStore()
        let a = MeshFixtures.floorQuad(), b = MeshFixtures.floorQuad()
        await store.upsert(a)
        await store.upsert(b)
        #expect(try await store.flush(to: tmp.url) == 2)
        #expect(try await store.flush(to: tmp.url) == 0)

        await store.remove(ids: [a.id])
        try await store.flush(to: tmp.url)
        #expect(!FileManager.default.fileExists(atPath: MeshStore.fileURL(for: a.id, in: tmp.url).path))

        try Data("garbage".utf8).write(to: tmp.url.appendingPathComponent("\(UUID().uuidString).bin"))
        let restored = MeshStore()
        let corrupt = try await restored.load(from: tmp.url)
        #expect(corrupt.count == 1)
        #expect(await restored.snapshot() == [b])
    }
}
