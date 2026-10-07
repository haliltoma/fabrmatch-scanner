import ARKit
import ScanLabCore

/// ARSession delegate on a private queue: selects keyframes, writes SLDF frames, fuses a preview cloud.
///
/// Safety invariant for `@unchecked Sendable`: mutable state is touched only on `queue`
/// (ARKit's `delegateQueue`), or via `queue.async`/`queue.sync` from the outside.
nonisolated final class TrueDepthRecorder: NSObject, ARSessionDelegate, @unchecked Sendable {
    static let range: ClosedRange<Float> = 0.10...0.80

    let queue = DispatchQueue(label: "scanlab.truedepth", qos: .userInitiated)
    private let writer: CaptureWriter
    private let onStatus: @Sendable (TrueDepthStatus) -> Void
    private var keyframes = KeyframePolicy(minTranslation: 0.03, minRotationDegrees: 5)
    private var fuser = PointCloudFuser(voxelSize: 0.0007, minConfidence: 2, depthRange: TrueDepthRecorder.range)
    private var recording = false
    private var lastDepthTimestamp: TimeInterval = -1
    private var lastStatus: TimeInterval = 0
    private var kept = 0
    private var received = 0

    init(writer: CaptureWriter, onStatus: @escaping @Sendable (TrueDepthStatus) -> Void) {
        self.writer = writer
        self.onStatus = onStatus
    }

    func setRecording(_ on: Bool) { queue.async { self.recording = on } }

    /// Fused preview points (meters, world) — call after recording stopped.
    func fusedPoints() -> [SIMD3<Float>] { queue.sync { fuser.points() } }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthData = frame.capturedDepthData, frame.capturedDepthDataTimestamp != lastDepthTimestamp else {
            report(frame, distance: nil)
            return
        }
        lastDepthTimestamp = frame.capturedDepthDataTimestamp
        received += 1
        guard let depthFrame = depthData.makeFrame(pose: frame.camera.transform, fallbackIntrinsics: frame.camera.intrinsics,
                                                   fallbackImageSize: frame.camera.imageResolution,
                                                   timestamp: frame.capturedDepthDataTimestamp, range: Self.range) else { return }
        // No tracking-state gate: in face-tracking configurations the camera only reports `.normal`
        // while a *face* is tracked, which never happens when scanning a part — the first field test
        // recorded zero frames. World tracking (enabled in the configuration) still poses each frame;
        // the motion thresholds below keep only frames that add a new viewpoint.
        if recording, keyframes.accept(pose: frame.camera.transform, time: frame.timestamp, trackingIsNormal: true) {
            kept += 1
            fuser.add(depthFrame)
            let writer = writer
            Task(priority: .utility) { try? await writer.append(depthFrame) }
        }
        report(frame, distance: Self.centralMedian(depthFrame))
    }

    private func report(_ frame: ARFrame, distance: Float?) {
        guard frame.timestamp - lastStatus >= 0.25 else { return }
        lastStatus = frame.timestamp
        onStatus(TrueDepthStatus(depthFrames: received, distance: distance, keyframes: kept, points: fuser.pointCount))
    }

    static func centralMedian(_ f: DepthFrame) -> Float? {
        var values: [Float] = []
        for v in (f.height / 3)..<(2 * f.height / 3) {
            for u in (f.width / 3)..<(2 * f.width / 3) where f.depth[v * f.width + u] > 0 {
                values.append(f.depth[v * f.width + u])
            }
        }
        guard values.count > 20 else { return nil }
        values.sort()
        return values[values.count / 2]
    }
}
