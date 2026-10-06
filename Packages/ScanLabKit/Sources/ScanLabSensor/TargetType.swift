public enum TargetType: String, Sendable, CaseIterable, Codable {
    case room
    case object
    case face
    /// Head, ear, hand: body parts scanned at close range.
    case bodyPart
    /// User scans themself while looking at the screen.
    case selfScan
    case unknown
}
