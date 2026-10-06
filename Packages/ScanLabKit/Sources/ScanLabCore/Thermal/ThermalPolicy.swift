import Foundation

/// Mirrors `ProcessInfo.ThermalState` so policy logic stays testable.
public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ThermalAction: Sendable, Equatable {
    case proceed
    case warn
    case saveAndStop
}

/// FR-3.8: warn at `.serious`, autosave and stop at `.critical`.
public enum ThermalPolicy {
    public static func action(for level: ThermalLevel) -> ThermalAction {
        switch level {
        case .nominal, .fair: .proceed
        case .serious: .warn
        case .critical: .saveAndStop
        }
    }
}
