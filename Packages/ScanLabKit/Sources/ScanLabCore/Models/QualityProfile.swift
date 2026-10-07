/// Capture quality presets (FR-3.7). Each preset tunes keyframe spacing and mesh refresh.
public enum QualityProfile: String, Codable, Sendable, CaseIterable {
    case fast
    case balanced
    case high

    /// Minimum camera translation between recorded keyframes, in meters.
    public var keyframeDistance: Float {
        switch self {
        case .fast: 0.30
        case .balanced: 0.15
        case .high: 0.08
        }
    }

    /// Minimum camera rotation between keyframes, degrees. Orbiting a small part, rotation — not
    /// translation — is what adds new viewpoints.
    public var keyframeAngle: Float {
        switch self {
        case .fast: 15
        case .balanced: 10
        case .high: 6
        }
    }

    /// Whether per-keyframe depth and confidence maps are written to disk.
    public var recordsDepth: Bool { self != .fast }
}
