public enum CaptureState: Sendable, Equatable {
    case idle
    case ready
    case scanning
    case paused
    case warning(CaptureWarning)
    case failed(String)
    case finished
}
