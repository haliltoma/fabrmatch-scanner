/// Decision thresholds. Starts with PRD M22 estimates; FR-22.5 comparison tests overwrite them.
public struct SensorProfile: Sendable, Equatable, Codable {
    /// Objects at or below this size (m) are "small" → TrueDepth candidates.
    public var smallObjectMaxSize: Float
    /// Objects above this size (m) or rooms → LiDAR.
    public var mediumObjectMaxSize: Float
    /// TrueDepth useful range, meters.
    public var trueDepthRange: ClosedRange<Float>
    /// Above this IR risk TrueDepth is not recommended.
    public var irRiskLimit: Float
    /// Above this surface difficulty depth sensors are unreliable → photogrammetry for small objects.
    public var difficultSurfaceLimit: Float

    public init(
        smallObjectMaxSize: Float = 0.40, mediumObjectMaxSize: Float = 2.0,
        trueDepthRange: ClosedRange<Float> = 0.15...0.50,
        irRiskLimit: Float = 0.6, difficultSurfaceLimit: Float = 0.6
    ) {
        self.smallObjectMaxSize = smallObjectMaxSize
        self.mediumObjectMaxSize = mediumObjectMaxSize
        self.trueDepthRange = trueDepthRange
        self.irRiskLimit = irRiskLimit
        self.difficultSurfaceLimit = difficultSurfaceLimit
    }

    public static let `default` = SensorProfile()
}
