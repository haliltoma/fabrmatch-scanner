import Foundation

/// Result of a finished capture. Holds file references only; large data never stays in RAM (PRD §4.3).
public struct ScanArtifact: Sendable, Equatable {
    public var record: ScanRecord
    public var scanDirectory: URL
    public var chunkFiles: [URL]
    public var framesDirectory: URL?

    public init(record: ScanRecord, scanDirectory: URL, chunkFiles: [URL], framesDirectory: URL? = nil) {
        self.record = record
        self.scanDirectory = scanDirectory
        self.chunkFiles = chunkFiles
        self.framesDirectory = framesDirectory
    }
}
