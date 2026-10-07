/// Per-frame summary sent from the ARKit queue to the UI.
nonisolated struct TrueDepthStatus: Sendable, Equatable {
    /// Depth frames delivered by the TrueDepth camera so far (diagnostics: 0 means no sensor data).
    var depthFrames: Int
    /// Median depth in the central region, meters; nil when nothing is in range.
    var distance: Float?
    var keyframes: Int
    var points: Int
}
