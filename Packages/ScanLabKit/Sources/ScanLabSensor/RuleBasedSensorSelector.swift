/// v1 transparent rule table from PRD M22 ("Başlangıç karar tablosu").
public struct RuleBasedSensorSelector: SensorSelecting {
    public init() {}

    public func recommend(from s: SensorSignals, profile p: SensorProfile) -> SensorRecommendation {
        let sunny = s.irInterferenceRisk >= p.irRiskLimit
        let difficult = s.surfaceDifficulty >= p.difficultSurfaceLimit

        switch s.targetType {
        case .selfScan:
            // Only the front sensor can see the user while they watch the screen.
            return SensorRecommendation(
                sensor: .trueDepth,
                reason: sunny ? "Kendini tarama ön kamerayı gerektirir; güneş ışığı derinliği bozabilir, gölgeye geçin." : "Kendini tarama: ön TrueDepth sensörü.",
                confidence: sunny ? 0.5 : 0.95
            )
        case .face, .bodyPart:
            if sunny {
                return SensorRecommendation(sensor: .lidar, reason: "Yüz/vücut hedefi ama güneş ışığı TrueDepth'i bozar; LiDAR öneriliyor.", confidence: 0.6, alternative: .trueDepth)
            }
            return SensorRecommendation(sensor: .trueDepth, reason: "Yüz/vücut yakın mesafe hedefi: TrueDepth daha ayrıntılı.", confidence: 0.9)
        case .room:
            return SensorRecommendation(sensor: .lidar, reason: "Oda/ortam: LiDAR geniş menzil ve dünya takibi sağlar.", confidence: 0.95)
        case .object, .unknown:
            return recommendForObject(s, p, sunny: sunny, difficult: difficult)
        }
    }

    private func recommendForObject(_ s: SensorSignals, _ p: SensorProfile, sunny: Bool, difficult: Bool) -> SensorRecommendation {
        guard let size = s.sizeEstimate ?? inferredSize(s) else {
            return SensorRecommendation(sensor: .lidar, reason: "Hedef boyutu bilinmiyor; varsayılan LiDAR.", confidence: 0.4)
        }
        if size > p.mediumObjectMaxSize {
            return SensorRecommendation(sensor: .lidar, reason: "Hedef \(meters(size)) — büyük alan için LiDAR.", confidence: 0.9)
        }
        if size > p.smallObjectMaxSize {
            return SensorRecommendation(sensor: .lidar, reason: "Orta boy nesne (\(meters(size))): LiDAR; doku için Object Capture da önerilir.", confidence: 0.75, alternative: .photogrammetry)
        }
        if difficult {
            return SensorRecommendation(sensor: .photogrammetry, reason: "Küçük, parlak/saydam yüzey: derinlik sensörleri güvenilmez; Object Capture veya mat sprey önerilir.", confidence: 0.7)
        }
        if sunny {
            return SensorRecommendation(sensor: .photogrammetry, reason: "Küçük nesne ama güneş ışığı TrueDepth'i bozar; fotogrametri önerilir.", confidence: 0.6, alternative: .lidar)
        }
        var reason = "Küçük mat nesne (\(meters(size))): TrueDepth, döner tabla ile en iyisi."
        if let d = s.distance, !p.trueDepthRange.contains(d) {
            reason += " Mesafe \(meters(d)); ideal \(meters(p.trueDepthRange.lowerBound))–\(meters(p.trueDepthRange.upperBound))."
        }
        return SensorRecommendation(sensor: .trueDepth, reason: reason, confidence: 0.85, alternative: .photogrammetry)
    }

    /// With no explicit size, a far target is treated as large (scene-scale).
    private func inferredSize(_ s: SensorSignals) -> Float? {
        guard let d = s.distance else { return nil }
        return d > 1 ? d : nil
    }

    private func meters(_ v: Float) -> String {
        v < 1 ? "\(Int((v * 100).rounded())) cm" : "\(Double(Int((v * 10).rounded())) / 10) m"
    }
}
