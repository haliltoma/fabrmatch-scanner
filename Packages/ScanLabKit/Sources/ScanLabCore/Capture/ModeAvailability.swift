/// Whether a capture mode can run on this device, and if not, what is missing (FR-1.2).
public enum ModeAvailability: Sendable, Equatable {
    case available
    case unavailable(missing: Set<Capability>)

    public init(required: Set<Capability>, supported: Set<Capability>) {
        let missing = required.subtracting(supported)
        self = missing.isEmpty ? .available : .unavailable(missing: missing)
    }

    public var isAvailable: Bool { self == .available }
}
