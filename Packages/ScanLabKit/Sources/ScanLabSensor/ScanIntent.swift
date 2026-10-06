/// User's priority preset (M22 "Kullanıcı niyeti").
public enum ScanIntent: String, Sendable, CaseIterable, Codable {
    case accuracy
    case visualDetail
    case speed
}
