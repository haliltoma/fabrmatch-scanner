/// Depth source used for a scan. Raw values match `project.json` (PRD §5.2).
public enum SensorKind: String, Codable, Sendable, CaseIterable {
    case lidar
    case trueDepth = "truedepth"
    case hybrid
    case photo
}
