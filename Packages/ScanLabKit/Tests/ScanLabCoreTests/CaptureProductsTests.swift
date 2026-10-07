import Foundation
import simd
import Testing
@testable import ScanLabCore

@Suite struct PointCloudFuserTests {
    /// A camera at the origin looking down −Z at a flat wall 1 m away.
    static func wallFrame(pose: simd_float4x4 = matrix_identity_float4x4) -> DepthFrame {
        DepthFrame(width: 8, height: 6, depth: [Float](repeating: 1, count: 48), confidence: [UInt8](repeating: 2, count: 48),
                   fx: 8, fy: 8, cx: 4, cy: 3, pose: pose, timestamp: 0)
    }

    @Test("Back-projection follows the ARKit convention: points land on z = −1")
    func backProjection() {
        var fuser = PointCloudFuser(voxelSize: 0.001)
        #expect(fuser.add(Self.wallFrame()) == 48)
        let pts = fuser.points()
        #expect(pts.count == 48)
        #expect(pts.allSatisfy { abs($0.z + 1) < 1e-6 })
        // Top-left pixel (u=0, v=0) is up-left of centre: x < 0, y > 0.
        #expect(pts.contains { $0.x < -0.4 && $0.y > 0.3 })
    }

    @Test("Repeated observations merge into voxels; low confidence and out-of-range pixels are skipped")
    func voxelMergeAndFilters() {
        var fuser = PointCloudFuser(voxelSize: 0.5, minConfidence: 2, depthRange: 0.1...0.9)
        #expect(fuser.add(Self.wallFrame()) == 0)  // 1 m is outside 0.1…0.9
        var f = Self.wallFrame()
        f.depth = [Float](repeating: 0.5, count: 48)
        f.confidence[0] = 1
        var coarse = PointCloudFuser(voxelSize: 0.5)
        #expect(coarse.add(f) == 47)
        #expect(coarse.add(f) == 47)
        #expect(coarse.pointCount <= 4)  // a 0.5×0.375 m patch spans few 0.5 m voxels
    }

    @Test func respectsMaxPoints() {
        var fuser = PointCloudFuser(voxelSize: 0.0001, maxPoints: 10)
        fuser.add(Self.wallFrame())
        #expect(fuser.pointCount == 10)
    }

    @Test("A fused cloud exports as a PLY with vertices only")
    func exportsAsMesh() {
        var fuser = PointCloudFuser(voxelSize: 0.01)
        fuser.add(Self.wallFrame())
        let mesh = fuser.mesh()
        #expect(mesh.triangleCount == 0 && mesh.vertexCount == 48)
    }
}

@Suite struct NerfstudioTransformsTests {
    @Test("transforms.json uses Nerfstudio keys and row-major matrices")
    func encodesNerfstudioFormat() throws {
        var t = NerfstudioTransforms(flX: 1400, flY: 1401, cx: 960, cy: 720, w: 1920, h: 1440)
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(1, 2, 3, 1)
        t.append(filePath: "images/000001.jpg", pose: pose)
        let json = try JSONSerialization.jsonObject(with: t.encoded()) as? [String: Any]
        #expect(json?["fl_x"] as? Double == 1400 && json?["w"] as? Int == 1920 && json?["camera_model"] as? String == "OPENCV")
        let frame = try #require((json?["frames"] as? [[String: Any]])?.first)
        #expect(frame["file_path"] as? String == "images/000001.jpg")
        let m = try #require(frame["transform_matrix"] as? [[Double]])
        #expect(m[0][3] == 1 && m[1][3] == 2 && m[2][3] == 3 && m[3] == [0, 0, 0, 1])
    }
}
