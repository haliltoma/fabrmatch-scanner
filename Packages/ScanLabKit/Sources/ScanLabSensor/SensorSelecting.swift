public protocol SensorSelecting: Sendable {
    func recommend(from signals: SensorSignals, profile: SensorProfile) -> SensorRecommendation
}
