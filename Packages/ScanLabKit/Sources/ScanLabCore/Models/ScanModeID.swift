/// Stable identifiers for capture modes, persisted in `project.json`.
public enum ScanModeID: String, Codable, Sendable, CaseIterable {
    case lidarMesh = "lidar_mesh"
    case pointCloud = "point_cloud"
    case objectCapture = "object_capture"
    case roomPlan = "room_plan"
    case trueDepth = "truedepth"
    case photoVideo = "photo_video"
}
