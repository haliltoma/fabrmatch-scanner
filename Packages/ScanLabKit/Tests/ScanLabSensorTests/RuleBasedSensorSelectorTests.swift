import Testing
@testable import ScanLabSensor

@Suite("M22 decision table")
struct RuleBasedSensorSelectorTests {
    let selector = RuleBasedSensorSelector()

    /// One case per row of the PRD M22 "Başlangıç karar tablosu".
    static let table: [(String, SensorSignals, RecommendedSensor)] = [
        ("Oda/ortam > 1 m", SensorSignals(targetType: .room, distance: 3), .lidar),
        ("Orta nesne 40 cm–2 m", SensorSignals(targetType: .object, distance: 1, sizeEstimate: 0.9), .lidar),
        ("Küçük mat nesne", SensorSignals(targetType: .object, distance: 0.3, sizeEstimate: 0.2), .trueDepth),
        ("Küçük parlak nesne", SensorSignals(targetType: .object, sizeEstimate: 0.2, surfaceDifficulty: 0.9), .photogrammetry),
        ("Yüz", SensorSignals(targetType: .face, distance: 0.3), .trueDepth),
        ("Kulak/el", SensorSignals(targetType: .bodyPart, distance: 0.25), .trueDepth),
        ("Kendini tarama", SensorSignals(targetType: .selfScan), .trueDepth),
        ("Güneşli dış mekân, küçük nesne", SensorSignals(targetType: .object, sizeEstimate: 0.2, irInterferenceRisk: 0.9), .photogrammetry),
        ("Güneşli dış mekân, sahne", SensorSignals(targetType: .unknown, distance: 4, irInterferenceRisk: 0.9), .lidar),
        ("Güneşte yüz", SensorSignals(targetType: .face, irInterferenceRisk: 0.9), .lidar),
    ]

    @Test(arguments: table)
    func decision(row: (String, SensorSignals, RecommendedSensor)) {
        let rec = selector.recommend(from: row.1, profile: .default)
        #expect(rec.sensor == row.2, "\(row.0): \(rec.reason)")
        #expect(!rec.reason.isEmpty)
        #expect((0...1).contains(rec.confidence))
    }

    @Test("Medium objects also suggest Object Capture")
    func mediumAlternative() {
        let rec = selector.recommend(from: SensorSignals(targetType: .object, sizeEstimate: 1), profile: .default)
        #expect(rec.alternative == .photogrammetry)
    }

    @Test("A calibrated profile moves the small/medium boundary (FR-22.5)")
    func profileChangesThresholds() {
        let signals = SensorSignals(targetType: .object, sizeEstimate: 0.5)
        #expect(selector.recommend(from: signals, profile: .default).sensor == .lidar)
        var calibrated = SensorProfile.default
        calibrated.smallObjectMaxSize = 0.6
        #expect(selector.recommend(from: signals, profile: calibrated).sensor == .trueDepth)
    }

    @Test func unknownSizeFallsBackToLidarWithLowConfidence() {
        let rec = selector.recommend(from: SensorSignals(), profile: .default)
        #expect(rec.sensor == .lidar)
        #expect(rec.confidence < 0.5)
    }

    @Test func outOfRangeDistanceIsExplained() {
        let rec = selector.recommend(from: SensorSignals(targetType: .object, distance: 0.8, sizeEstimate: 0.1), profile: .default)
        #expect(rec.sensor == .trueDepth)
        #expect(rec.reason.contains("ideal"))
    }
}
