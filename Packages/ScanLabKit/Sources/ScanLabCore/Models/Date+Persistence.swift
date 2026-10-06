import Foundation

extension Date {
    /// `project.json` stores ISO-8601 without fractional seconds; models round on creation
    /// so an in-memory value always equals what reads back from disk.
    public var persistable: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
}
