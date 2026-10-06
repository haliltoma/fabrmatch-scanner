import Foundation

/// Lightweight row for the library list (M2).
public struct ProjectSummary: Sendable, Equatable, Identifiable {
    public var project: Project
    public var paths: ProjectPaths
    public var sizeBytes: Int64

    public var id: UUID { project.id }
}
