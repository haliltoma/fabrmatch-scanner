import SwiftUI

extension Binding where Value == Bool {
    /// True while `optional` holds a value; setting false clears it. Used for error alerts.
    init<T: Sendable>(isPresent optional: Binding<T?>) {
        self.init(get: { optional.wrappedValue != nil }, set: { if !$0 { optional.wrappedValue = nil } })
    }
}
