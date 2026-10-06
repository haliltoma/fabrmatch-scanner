/// Disk usage split for FR-2.6 ("ham veri vs işlenmiş veri").
public struct StorageSummary: Sendable, Equatable {
    public var rawBytes: Int64
    public var processedBytes: Int64
    public var totalBytes: Int64
}
