import ARKit
import AVFoundation
import ScanLabCore

extension AVDepthData {
    /// Copies TrueDepth depth into a `DepthFrame` posed with the ARKit camera transform.
    ///
    /// Intrinsics come from the depth data's own calibration (scaled from its reference size to the
    /// depth map): the front color image and the depth map need not share an aspect ratio, so
    /// scaling `ARCamera.intrinsics` would distort the geometry. TrueDepth has no per-pixel
    /// confidence; valid pixels inside `range` get confidence 2.
    nonisolated func makeFrame(pose: simd_float4x4, fallbackIntrinsics: simd_float3x3, fallbackImageSize: CGSize,
                               timestamp: TimeInterval, range: ClosedRange<Float>) -> DepthFrame? {
        let data = depthDataType == kCVPixelFormatType_DepthFloat32 ? self : converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = data.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(map)
        var depth = [Float](repeating: 0, count: w * h)
        var confidence = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let d = line[x]
                if d.isFinite, range.contains(d) {
                    depth[y * w + x] = d
                    confidence[y * w + x] = 2
                }
            }
        }
        let k: (fx: Float, fy: Float, cx: Float, cy: Float)
        if let cal = data.cameraCalibrationData {
            let m = cal.intrinsicMatrix
            let ref = cal.intrinsicMatrixReferenceDimensions
            let sx = Float(w) / Float(ref.width), sy = Float(h) / Float(ref.height)
            k = (m[0][0] * sx, m[1][1] * sy, m[2][0] * sx, m[2][1] * sy)
        } else {
            k = DepthFrame.intrinsics(fromImage: fallbackIntrinsics,
                                      imageSize: SIMD2(Float(fallbackImageSize.width), Float(fallbackImageSize.height)),
                                      depthSize: SIMD2(Float(w), Float(h)))
        }
        return DepthFrame(width: w, height: h, depth: depth, confidence: confidence,
                          fx: k.fx, fy: k.fy, cx: k.cx, cy: k.cy, pose: pose, timestamp: timestamp)
    }
}
