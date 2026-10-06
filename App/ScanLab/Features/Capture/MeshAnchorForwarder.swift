import ARKit
import ScanLabCore

/// ARSession delegate running on a private serial queue (PRD §4.4: no heavy work on the main thread).
/// It only copies anchors into `MeshChunk`s, range-filters them and hands them to the `MeshStore` actor.
///
/// Safety invariant for `@unchecked Sendable`: all mutable state (`versions`, `lastCamera`,
/// `lastStatusTime`, `maxRange`) is touched only on `queue`, which ARKit uses as `delegateQueue`.
nonisolated final class MeshAnchorForwarder: NSObject, ARSessionDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "scanlab.arkit.delegate", qos: .userInitiated)
    private let store: MeshStore
    private let onStatus: @Sendable (FrameStatus) -> Void
    private let onInterruption: @Sendable (Bool) -> Void

    private var versions: [UUID: UInt64] = [:]
    private var lastCamera: (position: SIMD3<Float>, time: TimeInterval)?
    private var lastStatusTime: TimeInterval = 0
    private var maxRange: Float = 5

    init(store: MeshStore, onStatus: @escaping @Sendable (FrameStatus) -> Void, onInterruption: @escaping @Sendable (Bool) -> Void) {
        self.store = store
        self.onStatus = onStatus
        self.onInterruption = onInterruption
    }

    func setMaxRange(_ meters: Float) {
        queue.async { self.maxRange = meters }
    }

    // MARK: Anchors

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { forward(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { forward(anchors) }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier }
        guard !ids.isEmpty else { return }
        ids.forEach { versions.removeValue(forKey: $0) }
        let store = store
        Task { await store.remove(ids: ids) }
    }

    private func forward(_ anchors: [ARAnchor]) {
        let camera = lastCamera?.position
        let range = maxRange
        var chunks: [MeshChunk] = []
        for case let anchor as ARMeshAnchor in anchors {
            let version = (versions[anchor.identifier] ?? 0) + 1
            versions[anchor.identifier] = version
            let chunk = anchor.makeChunk(version: version)
            chunks.append(camera.map { chunk.filtered(maxDistance: range, from: $0) } ?? chunk)
        }
        guard !chunks.isEmpty else { return }
        let store = store
        Task {
            for chunk in chunks { await store.upsert(chunk) }
        }
    }

    // MARK: Frames → HUD (throttled to ~5 Hz)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let t = frame.timestamp
        let c = frame.camera.transform.columns.3
        let position = SIMD3<Float>(c.x, c.y, c.z)
        var speed: Float = 0
        if let last = lastCamera, t > last.time {
            speed = simd_distance(position, last.position) / Float(t - last.time)
        }
        lastCamera = (position, t)
        guard t - lastStatusTime >= 0.2 else { return }
        lastStatusTime = t
        onStatus(FrameStatus(warning: Self.warning(for: frame.camera.trackingState, speed: speed), speed: speed, cameraPosition: position))
    }

    /// FR-3.4 guidance messages.
    static func warning(for tracking: ARCamera.TrackingState, speed: Float) -> CaptureWarning? {
        switch tracking {
        case .notAvailable: return .initializing
        case .limited(.initializing): return .initializing
        case .limited(.excessiveMotion): return .excessiveMotion
        case .limited(.insufficientFeatures): return .insufficientFeatures
        case .limited(.relocalizing): return .relocalizing
        case .limited: return .initializing
        case .normal: return speed > 0.6 ? .excessiveMotion : nil
        }
    }

    // MARK: Interruptions (FR-3.9)

    func sessionWasInterrupted(_ session: ARSession) { onInterruption(true) }
    func sessionInterruptionEnded(_ session: ARSession) { onInterruption(false) }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }
}
