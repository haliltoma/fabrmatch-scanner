import Foundation
import simd
import Testing
@testable import ScanLabCore

@Suite struct RawCaptureTests {
    static let golden = URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../fixtures/frame_v1.sldf").standardized

    static func goldenFrame() -> DepthFrame {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(0.1, 0.2, 0.3, 1)
        return DepthFrame(width: 4, height: 3,
                          depth: [0.25, 0.5, 0, 1, 0.3, 0.31, 0.32, 0.33, 2, 0, 0.125, 0.75],
                          confidence: [2, 1, 0, 2, 2, 2, 2, 2, 0, 0, 1, 2],
                          fx: 200, fy: 201, cx: 2, cy: 1.5, pose: pose, timestamp: 12.5)
    }

    @Test("Swift encoder matches fixtures/frame_v1.sldf byte for byte")
    func goldenFile() throws {
        #expect(DepthFrameCodec.encode(Self.goldenFrame()) == (try Data(contentsOf: Self.golden)))
        #expect(try DepthFrameCodec.decode(Data(contentsOf: Self.golden)) == Self.goldenFrame())
    }

    @Test(arguments: [0, 20, 100, 163])
    func truncatedFramesThrow(length: Int) {
        let data = DepthFrameCodec.encode(Self.goldenFrame()).prefix(length)
        #expect(throws: (any Error).self) { try DepthFrameCodec.decode(data) }
    }

    @Test func intrinsicsScaleToDepthResolution() {
        let k = simd_float3x3(SIMD3(1600, 0, 0), SIMD3(0, 1600, 0), SIMD3(960, 720, 1))
        let s = DepthFrame.intrinsics(fromImage: k, imageSize: SIMD2(1920, 1440), depthSize: SIMD2(256, 192))
        #expect(abs(s.fx - 213.333) < 0.01 && abs(s.cx - 128) < 0.001 && abs(s.cy - 96) < 0.001)
    }

    static func orbitPose(degrees: Float) -> simd_float4x4 {
        let a = degrees * .pi / 180
        let eye = SIMD3<Float>(0.4 * cos(a), 0.4 * sin(a), 0.15)
        let back = simd_normalize(eye)
        let right = simd_normalize(simd_cross(SIMD3(0, 0, 1), back))
        let up = simd_cross(back, right)
        return simd_float4x4(SIMD4(right, 0), SIMD4(up, 0), SIMD4(back, 0), SIMD4(eye, 1))
    }

    @Test("Orbiting a part: keyframes every ~10° (balanced profile)")
    func keyframesFollowRotation() {
        var policy = KeyframePolicy(profile: .balanced)
        var kept = 0
        for step in 0..<360 {  // 1° per frame, 0.2 s apart
            if policy.accept(pose: Self.orbitPose(degrees: Float(step)), time: Double(step) * 0.2, trackingIsNormal: true) {
                kept += 1
            }
        }
        // Looking down ~20°, the view direction turns cos(20.6°) ≈ 0.94° per 1° of orbit → ≈ 337°/10° ≈ 33.
        #expect((32...35).contains(kept))
    }

    @Test func rejectsLimitedTrackingAndTooFastFrames() {
        var policy = KeyframePolicy(profile: .high)
        let limited = policy.accept(pose: Self.orbitPose(degrees: 0), time: 0, trackingIsNormal: false)
        let first = policy.accept(pose: Self.orbitPose(degrees: 0), time: 0, trackingIsNormal: true)
        let tooSoon = policy.accept(pose: Self.orbitPose(degrees: 30), time: 0.05, trackingIsNormal: true)
        let tooClose = policy.accept(pose: Self.orbitPose(degrees: 1), time: 1, trackingIsNormal: true)
        let turned = policy.accept(pose: Self.orbitPose(degrees: 7), time: 2, trackingIsNormal: true)
        #expect(!limited && first && !tooSoon && !tooClose && turned)
    }

    @Test func manifestMatchesPythonLoader() throws {
        let m = CaptureManifest(sensor: .trueDepth, frames: [CaptureManifest.frameName(1)])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as? [String: Any]
        #expect(json?["format"] as? String == "scanlab-capture")
        #expect(json?["sensor"] as? String == "truedepth")
        #expect((json?["frames"] as? [String]) == ["depth/000001.sldf"])
    }
}

@Suite struct CaptureWriterTests {
    @Test("Writer produces a folder the Mac loader accepts")
    func writesFramesAndManifest() async throws {
        let tmp = try TemporaryDirectory()
        let writer = CaptureWriter(directory: tmp.url, sensor: .lidar)
        try await writer.append(RawCaptureTests.goldenFrame())
        try await writer.append(RawCaptureTests.goldenFrame())
        try await writer.flush()
        let manifest = try JSONDecoder().decode(CaptureManifest.self, from: Data(contentsOf: tmp.url.appendingPathComponent("capture.json")))
        #expect(manifest.frames == ["depth/000001.sldf", "depth/000002.sldf"] && manifest.sensor == "lidar")
        let second = try Data(contentsOf: tmp.url.appendingPathComponent(manifest.frames[1]))
        #expect(try DepthFrameCodec.decode(second) == RawCaptureTests.goldenFrame())
    }
}
