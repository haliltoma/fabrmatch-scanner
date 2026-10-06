/// Display and export units (M18). Internal geometry is always in meters.
public enum LengthUnit: String, Codable, Sendable, CaseIterable {
    case meters
    case centimeters
    case millimeters
    case feet
    case inches

    public var metersPerUnit: Double {
        switch self {
        case .meters: 1
        case .centimeters: 0.01
        case .millimeters: 0.001
        case .feet: 0.3048
        case .inches: 0.0254
        }
    }

    public var symbol: String {
        switch self {
        case .meters: "m"
        case .centimeters: "cm"
        case .millimeters: "mm"
        case .feet: "ft"
        case .inches: "in"
        }
    }

    /// Converts a length in meters into this unit.
    public func fromMeters(_ meters: Double) -> Double { meters / metersPerUnit }
}
