import ScanLabCore

/// Static description of a capture mode for the mode picker (PRD §8 screen 1).
struct CaptureModeDescriptor: Identifiable, Hashable {
    let id: ScanModeID
    let title: String
    let subtitle: String
    let systemImage: String
    let requiredCapabilities: Set<Capability>
    /// Roadmap phase that delivers the mode; nil once implemented.
    let plannedPhase: String?

    var isImplemented: Bool { plannedPhase == nil }

    static let all: [CaptureModeDescriptor] = [
        .init(id: .lidarMesh, title: "Oda / Ortam", subtitle: "LiDAR mesh, sınıflandırmalı", systemImage: "cube.transparent",
              requiredCapabilities: [.lidarMesh, .sceneDepth], plannedPhase: nil),
        .init(id: .trueDepth, title: "Yüz / Yakın nesne", subtitle: "TrueDepth ön kamera — küçük parçalar için en ayrıntılı",
              systemImage: "face.dashed", requiredCapabilities: [.trueDepth, .faceTracking], plannedPhase: nil),
        .init(id: .objectCapture, title: "Nesne", subtitle: "Fotogrametri, dokulu model", systemImage: "camera.metering.center.weighted",
              requiredCapabilities: [.objectCapture], plannedPhase: nil),
        .init(id: .roomPlan, title: "Oda planı", subtitle: "Duvar, kapı, pencere, mobilya", systemImage: "square.split.bottomrightquarter",
              requiredCapabilities: [.roomPlan], plannedPhase: nil),
        .init(id: .pointCloud, title: "Nokta bulutu", subtitle: "LiDAR derinliğinden nokta bulutu (PLY)", systemImage: "circle.grid.3x3",
              requiredCapabilities: [.sceneDepth], plannedPhase: nil),
        .init(id: .photoVideo, title: "Foto / Video", subtitle: "Gaussian Splatting için kare + konum paketi", systemImage: "video",
              requiredCapabilities: [], plannedPhase: nil),
    ]
}
