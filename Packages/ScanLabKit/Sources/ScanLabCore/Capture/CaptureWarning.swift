/// Non-fatal conditions surfaced in the scanning HUD (FR-3.4, FR-3.8).
public enum CaptureWarning: String, Sendable, Equatable, CaseIterable {
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case thermalSerious
    case lowDiskSpace
    case memoryPressure
}
