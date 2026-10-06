import ScanLabCore

extension Capability {
    var displayName: String {
        switch self {
        case .lidarMesh: "LiDAR sahne yeniden yapılandırma"
        case .sceneDepth: "LiDAR derinlik"
        case .trueDepth: "TrueDepth ön kamera"
        case .faceTracking: "Yüz takibi"
        case .roomPlan: "RoomPlan"
        case .objectCapture: "Object Capture"
        }
    }
}

extension ModeAvailability {
    /// FR-1.2: explains why a mode is disabled.
    var unavailableReason: String? {
        guard case .unavailable(let missing) = self else { return nil }
        let names = missing.map(\.displayName).sorted().joined(separator: ", ")
        return "Bu cihazda desteklenmiyor: \(names)"
    }
}
