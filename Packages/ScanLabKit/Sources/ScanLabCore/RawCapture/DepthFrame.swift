import Foundation
import simd

/// One raw depth frame for multi-algorithm reconstruction on the Mac (`scanlab-mac/scanlab/recon`).
/// Camera convention is ARKit's: +X right, +Y up, looking down −Z; pixel rows grow downward.
public struct DepthFrame: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// Row-major meters, 0 = invalid.
    public var depth: [Float]
    /// Row-major ARConfidenceLevel raw values (0 low, 1 medium, 2 high).
    public var confidence: [UInt8]
    /// Intrinsics at the depth map's resolution.
    public var fx: Float, fy: Float, cx: Float, cy: Float
    /// Camera → world.
    public var pose: simd_float4x4
    public var timestamp: Double

    public init(width: Int, height: Int, depth: [Float], confidence: [UInt8],
                fx: Float, fy: Float, cx: Float, cy: Float, pose: simd_float4x4, timestamp: Double) {
        precondition(depth.count == width * height && confidence.count == width * height, "buffer size mismatch")
        self.width = width
        self.height = height
        self.depth = depth
        self.confidence = confidence
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.pose = pose
        self.timestamp = timestamp
    }

    /// Scales full-image intrinsics (ARCamera.intrinsics, column-major 3×3) to the depth map size.
    public static func intrinsics(fromImage k: simd_float3x3, imageSize: SIMD2<Float>, depthSize: SIMD2<Float>)
        -> (fx: Float, fy: Float, cx: Float, cy: Float) {
        let s = depthSize / imageSize
        return (k[0][0] * s.x, k[1][1] * s.y, k[2][0] * s.x, k[2][1] * s.y)
    }
}
