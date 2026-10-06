import Foundation

/// Contents of `project.json` (PRD §5.2).
public struct Project: Codable, Sendable, Equatable, Identifiable {
    /// Bump together with a migration step in `ProjectMigrator`.
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var tags: [String]
    public var scans: [ScanRecord]
    public var units: LengthUnit
    public var schemaVersion: Int
    /// Set while the project sits in the trash (FR-2.3).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        tags: [String] = [],
        scans: [ScanRecord] = [],
        units: LengthUnit = .meters,
        schemaVersion: Int = Project.currentSchemaVersion,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt.persistable
        self.tags = tags
        self.scans = scans
        self.units = units
        self.schemaVersion = schemaVersion
        self.deletedAt = deletedAt?.persistable
    }

    public var modes: Set<ScanModeID> { Set(scans.map(\.mode)) }
    public var containsFace: Bool { scans.contains(where: \.containsFace) }
}
