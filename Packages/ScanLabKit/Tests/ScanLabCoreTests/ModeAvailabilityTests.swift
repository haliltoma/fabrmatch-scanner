import Testing
@testable import ScanLabCore

@Suite struct ModeAvailabilityTests {
    @Test("Device without LiDAR reports the missing capability (FR-1.2)")
    func missingLidar() {
        let a = ModeAvailability(required: [.lidarMesh, .sceneDepth], supported: [.trueDepth, .faceTracking])
        #expect(a == .unavailable(missing: [.lidarMesh, .sceneDepth]))
        #expect(!a.isAvailable)
    }

    @Test func available() {
        #expect(ModeAvailability(required: [.lidarMesh], supported: Set(Capability.allCases)).isAvailable)
    }
}
