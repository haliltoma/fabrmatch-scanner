/// Inputs gathered during the 2–3 s pre-scan (FR-22.1). Unknown values are nil.
public struct SensorSignals: Sendable, Equatable {
    public var targetType: TargetType
    /// Median distance to the target, meters.
    public var distance: Float?
    /// Largest bounding-box dimension of the target, meters.
    public var sizeEstimate: Float?
    /// 0…1, high in direct sunlight (IR interference hurts TrueDepth).
    public var irInterferenceRisk: Float
    /// 0…1, high for shiny / transparent / very dark surfaces.
    public var surfaceDifficulty: Float
    public var intent: ScanIntent

    public init(
        targetType: TargetType = .unknown, distance: Float? = nil, sizeEstimate: Float? = nil,
        irInterferenceRisk: Float = 0, surfaceDifficulty: Float = 0, intent: ScanIntent = .accuracy
    ) {
        self.targetType = targetType
        self.distance = distance
        self.sizeEstimate = sizeEstimate
        self.irInterferenceRisk = irInterferenceRisk
        self.surfaceDifficulty = surfaceDifficulty
        self.intent = intent
    }
}
