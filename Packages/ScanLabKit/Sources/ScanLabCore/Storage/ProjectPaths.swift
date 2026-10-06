import Foundation

/// Folder layout of one project (PRD §5.1).
public struct ProjectPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var manifest: URL { root.appendingPathComponent("project.json") }
    public var thumbnail: URL { root.appendingPathComponent("thumbnail.jpg") }
    public var scans: URL { root.appendingPathComponent("scans", isDirectory: true) }
    public var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }
    public var exports: URL { root.appendingPathComponent("exports", isDirectory: true) }
    public var measurements: URL { root.appendingPathComponent("measurements.json") }
    public var annotations: URL { root.appendingPathComponent("annotations.json") }

    public func scan(_ id: UUID) -> ScanPaths { ScanPaths(root: scans.appendingPathComponent(id.uuidString, isDirectory: true)) }
}

/// Folder layout of one scan inside a project (PRD §5.1).
public struct ScanPaths: Sendable, Equatable {
    public let root: URL

    public var raw: URL { root.appendingPathComponent("raw", isDirectory: true) }
    public var meshChunks: URL { raw.appendingPathComponent("mesh_chunks", isDirectory: true) }
    public var frames: URL { raw.appendingPathComponent("frames", isDirectory: true) }
    public var depth: URL { raw.appendingPathComponent("depth", isDirectory: true) }
    public var confidence: URL { raw.appendingPathComponent("conf", isDirectory: true) }
    public var worldMap: URL { raw.appendingPathComponent("worldmap.arworldmap") }
    public var manifest: URL { root.appendingPathComponent("scan.json") }
}
