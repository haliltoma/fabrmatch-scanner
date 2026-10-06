import ScanLabCore

extension CaptureWarning {
    /// FR-3.4 guidance text.
    var message: String {
        switch self {
        case .initializing: "Başlatılıyor — telefonu yavaşça hareket ettir"
        case .excessiveMotion: "Yavaşla"
        case .insufficientFeatures: "Yetersiz ayrıntı — daha dokulu bir alana yönel"
        case .relocalizing: "Konum yeniden bulunuyor — önceki alana dön"
        case .thermalSerious: "Cihaz ısınıyor — kısa bir mola önerilir"
        case .lowDiskSpace: "Depolama azaldı"
        case .memoryPressure: "Bellek sınırına yaklaşıldı"
        }
    }

    var systemImage: String {
        switch self {
        case .thermalSerious: "thermometer.high"
        case .excessiveMotion: "tortoise"
        default: "exclamationmark.triangle"
        }
    }
}
