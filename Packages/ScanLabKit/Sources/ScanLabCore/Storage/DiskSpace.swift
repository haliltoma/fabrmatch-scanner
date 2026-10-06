import Foundation

/// Pre-scan free space check (PRD §5.3: warn below 1 GB).
public enum DiskSpace {
    public static let minimumFreeBytes: Int64 = 1_000_000_000

    public static func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    public static func isLow(availableBytes: Int64) -> Bool { availableBytes < minimumFreeBytes }
}
