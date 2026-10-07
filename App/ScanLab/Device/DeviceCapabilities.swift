import ARKit
import AVFoundation
import RealityKit
import RoomPlan
import ScanLabCore
import SwiftUI  // ObjectCaptureSession lives in the RealityKit+SwiftUI cross-import overlay

/// FR-1.1 capability probe. On the simulator or devices without LiDAR every check fails
/// and the app runs in restricted mode instead of crashing.
enum DeviceCapabilities {
    static func detect() -> Set<Capability> {
        var result: Set<Capability> = []
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) { result.insert(.lidarMesh) }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { result.insert(.sceneDepth) }
        if AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil { result.insert(.trueDepth) }
        if ARFaceTrackingConfiguration.isSupported { result.insert(.faceTracking) }
        if RoomCaptureSession.isSupported { result.insert(.roomPlan) }
        if ObjectCaptureSession.isSupported { result.insert(.objectCapture) }
        return result
    }
}
