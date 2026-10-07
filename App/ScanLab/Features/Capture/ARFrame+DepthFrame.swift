import ARKit
import ScanLabCore

extension ARFrame {
    /// Copies LiDAR scene depth + confidence out of the frame (never retain the ARFrame itself:
    /// it pins camera buffers and stalls the session). Uses raw `sceneDepth`, not the temporally
    /// smoothed variant, so the Mac's algorithms see independent per-frame measurements.
    nonisolated func makeDepthFrame() -> DepthFrame? {
        guard let scene = sceneDepth, let confidenceMap = scene.confidenceMap else { return nil }
        let depthMap = scene.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }
        let w = CVPixelBufferGetWidth(depthMap), h = CVPixelBufferGetHeight(depthMap)
        guard let dBase = CVPixelBufferGetBaseAddress(depthMap), let cBase = CVPixelBufferGetBaseAddress(confidenceMap),
              CVPixelBufferGetWidth(confidenceMap) == w, CVPixelBufferGetHeight(confidenceMap) == h else { return nil }
        let dRow = CVPixelBufferGetBytesPerRow(depthMap), cRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        var depth = [Float](repeating: 0, count: w * h)
        var confidence = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let dLine = dBase.advanced(by: y * dRow).assumingMemoryBound(to: Float32.self)
            let cLine = cBase.advanced(by: y * cRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let d = dLine[x]
                depth[y * w + x] = d.isFinite && d > 0 ? d : 0
                confidence[y * w + x] = cLine[x]
            }
        }
        let size = camera.imageResolution
        let k = DepthFrame.intrinsics(fromImage: camera.intrinsics,
                                      imageSize: SIMD2(Float(size.width), Float(size.height)),
                                      depthSize: SIMD2(Float(w), Float(h)))
        return DepthFrame(width: w, height: h, depth: depth, confidence: confidence,
                          fx: k.fx, fy: k.fy, cx: k.cx, cy: k.cy, pose: camera.transform, timestamp: timestamp)
    }
}
