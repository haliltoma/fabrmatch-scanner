/// Per-frame summary sent from the ARKit queue to the UI.
nonisolated struct TrueDepthStatus: Sendable, Equatable {
    var trackingNormal: Bool
    /// Median depth in the central region, meters; nil when nothing is in range.
    var distance: Float?
    var keyframes: Int
    var points: Int
}
