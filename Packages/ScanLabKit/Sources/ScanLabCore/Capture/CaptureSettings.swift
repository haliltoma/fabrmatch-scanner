public struct CaptureSettings: Sendable, Equatable {
    public var quality: QualityProfile
    /// Geometry farther than this from the camera is not added (FR-3.5), meters.
    public var maxRange: Float
    /// Keep raw frames/depth for reprocessing (PRD §5.3).
    public var keepRawData: Bool
    /// Vertex weld tolerance used when merging chunks, meters.
    public var weldTolerance: Float

    public init(quality: QualityProfile = .balanced, maxRange: Float = 5, keepRawData: Bool = true, weldTolerance: Float = 0.005) {
        self.quality = quality
        self.maxRange = maxRange
        self.keepRawData = keepRawData
        self.weldTolerance = weldTolerance
    }
}
