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

    /// Whether per-keyframe depth and confidence maps are written to disk.
    public var recordsDepth: Bool { self != .fast }
}
