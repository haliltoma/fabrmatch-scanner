import Foundation

/// Per-test scratch directory so tests stay parallel-safe.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLabTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
