/// Hardware/OS features a capture mode can depend on (FR-1.1).
public enum Capability: String, Sendable, Hashable, CaseIterable, Codable {
    case lidarMesh
    case sceneDepth
    case trueDepth
    case faceTracking
    case roomPlan
    case objectCapture
}
