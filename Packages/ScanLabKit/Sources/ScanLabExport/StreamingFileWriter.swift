import Foundation

/// Buffers writes and flushes in large blocks so huge meshes stream to disk without
/// building the whole file in memory (M13: "büyük dosyada akışla yazma").
/// Writes to a temporary file and moves it into place on `finish()` for atomicity.
struct StreamingFileWriter {
    private let destination: URL
    private let temporary: URL
    private let handle: FileHandle
    private var buffer = Data()
    private let flushThreshold = 1 << 20

    init(url: URL) throws {
        destination = url
        temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        handle = try FileHandle(forWritingTo: temporary)
        buffer.reserveCapacity(flushThreshold)
    }

    mutating func write(_ data: Data) throws {
        buffer.append(data)
        if buffer.count >= flushThreshold { try flush() }
    }

    mutating func write(_ string: String) throws { try write(Data(string.utf8)) }

    mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    mutating func finish() throws {
        try flush()
        try handle.close()
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    func abandon() {
        try? handle.close()
        try? FileManager.default.removeItem(at: temporary)
    }
}
