import ScanLabCore

/// Small per-frame summary sent from the ARKit queue to the UI (never the ARFrame itself,
/// which would retain camera buffers and stall capture).
nonisolated struct FrameStatus: Sendable, Equatable {
    var warning: CaptureWarning?
    /// Camera speed, m/s.
    var speed: Float
    var cameraPosition: SIMD3<Float>
}
