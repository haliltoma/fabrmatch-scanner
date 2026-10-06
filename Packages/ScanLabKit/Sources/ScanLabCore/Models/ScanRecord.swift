import Foundation

/// One capture inside a project (PRD §5.2 `scans[]`).
public struct ScanRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var mode: ScanModeID
    public var sensor: SensorKind
    public var createdAt: Date
    public var device: String
    public var stats: ScanStats
    public var qualityProfile: QualityProfile
    /// Row-major 4x4 transform from scan space into project space.
    public var transformToProject: [[Float]]
    /// Why the sensor was chosen (FR-22.7). Nil for manual selection.
    public var selectionReason: String?
    public var qualityScore: Float?
    /// Scans of faces need extra consent before sharing (FR-21.10).
    public var containsFace: Bool

    public static let identityTransform: [[Float]] = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]

    public init(
        id: UUID = UUID(),
        mode: ScanModeID,
        sensor: SensorKind,
        createdAt: Date,
        device: String,
        stats: ScanStats = ScanStats(),
        qualityProfile: QualityProfile = .balanced,
        transformToProject: [[Float]] = ScanRecord.identityTransform,
        selectionReason: String? = nil,
        qualityScore: Float? = nil,
        containsFace: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.sensor = sensor
        self.createdAt = createdAt.persistable
        self.device = device
        self.stats = stats
        self.qualityProfile = qualityProfile
        self.transformToProject = transformToProject
        self.selectionReason = selectionReason
        self.qualityScore = qualityScore
        self.containsFace = containsFace
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, sensor, createdAt, device, stats, qualityProfile, transformToProject
        case selectionReason, qualityScore, containsFace
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mode = try c.decode(ScanModeID.self, forKey: .mode)
        sensor = try c.decode(SensorKind.self, forKey: .sensor)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        device = try c.decode(String.self, forKey: .device)
        stats = try c.decodeIfPresent(ScanStats.self, forKey: .stats) ?? ScanStats()
        qualityProfile = try c.decodeIfPresent(QualityProfile.self, forKey: .qualityProfile) ?? .balanced
        transformToProject = try c.decodeIfPresent([[Float]].self, forKey: .transformToProject) ?? Self.identityTransform
        selectionReason = try c.decodeIfPresent(String.self, forKey: .selectionReason)
        qualityScore = try c.decodeIfPresent(Float.self, forKey: .qualityScore)
        containsFace = try c.decodeIfPresent(Bool.self, forKey: .containsFace) ?? false
    }
}
