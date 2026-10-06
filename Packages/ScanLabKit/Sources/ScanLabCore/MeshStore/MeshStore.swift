import Foundation

/// Chunk-based live mesh store fed by ARKit anchor events (PRD §4.4–4.5).
///
/// Delegate callbacks only copy anchor data into `MeshChunk` values and hand them here;
/// renderers and exporters take `snapshot()`s instead of sharing mutable state.
public actor MeshStore {
    private var chunks: [UUID: MeshChunk] = [:]
    private var dirty: Set<UUID> = []
    private var removedSinceFlush: Set<UUID> = []

    public init() {}

    /// Inserts or replaces a chunk. Returns false when an equal or newer version is already stored.
    @discardableResult
    public func upsert(_ chunk: MeshChunk) -> Bool {
        if let existing = chunks[chunk.id], existing.version >= chunk.version { return false }
        chunks[chunk.id] = chunk
        dirty.insert(chunk.id)
        removedSinceFlush.remove(chunk.id)
        return true
    }

    public func remove(ids: some Sequence<UUID>) {
        for id in ids where chunks.removeValue(forKey: id) != nil {
            dirty.remove(id)
            removedSinceFlush.insert(id)
        }
    }

    public func removeAll() {
        removedSinceFlush.formUnion(chunks.keys)
        chunks.removeAll()
        dirty.removeAll()
    }

    /// Chunks sorted by id so downstream processing is deterministic.
    public func snapshot() -> [MeshChunk] {
        chunks.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public var stats: MeshStoreStats {
        chunks.values.reduce(into: MeshStoreStats(chunkCount: chunks.count, vertexCount: 0, triangleCount: 0)) {
            $0.vertexCount += $1.vertices.count
            $0.triangleCount += $1.triangleCount
        }
    }

    /// Writes changed chunks to `directory` and deletes files of removed chunks (autosave, PRD §5.3).
    /// Returns the number of files written.
    @discardableResult
    public func flush(to directory: URL) throws -> Int {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        for id in dirty {
            guard let chunk = chunks[id] else { continue }
            try MeshChunkCodec.encode(chunk).write(to: Self.fileURL(for: id, in: directory), options: .atomic)
            written += 1
        }
        for id in removedSinceFlush {
            try? FileManager.default.removeItem(at: Self.fileURL(for: id, in: directory))
        }
        dirty.removeAll()
        removedSinceFlush.removeAll()
        return written
    }

    /// Restores chunks written by `flush(to:)`, e.g. for crash recovery. Corrupt files are skipped and reported.
    public func load(from directory: URL) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bin" }
        var corrupt: [URL] = []
        for file in files {
            do {
                let chunk = try MeshChunkCodec.decode(Data(contentsOf: file))
                chunks[chunk.id] = chunk
            } catch {
                corrupt.append(file)
            }
        }
        dirty.removeAll()
        return corrupt
    }

    public static func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).bin")
    }
}
