public struct SensorRecommendation: Sendable, Equatable {
    public var sensor: RecommendedSensor
    /// Human-readable justification shown to the user (FR-22.1) and stored in `scan.json` (FR-22.7).
    public var reason: String
    /// 0…1
    public var confidence: Float
    /// Secondary option worth suggesting, e.g. Object Capture for medium objects.
    public var alternative: RecommendedSensor?

    public init(sensor: RecommendedSensor, reason: String, confidence: Float, alternative: RecommendedSensor? = nil) {
        self.sensor = sensor
        self.reason = reason
        self.confidence = confidence
        self.alternative = alternative
    }
}
