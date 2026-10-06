enum ScanPhase: Equatable {
    case preparing
    case ready
    case scanning
    case paused
    case saving
    case finished
    case failed(String)
}
