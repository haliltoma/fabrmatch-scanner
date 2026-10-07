import Foundation
import ScanLabCore

/// What the scan screen should capture and where to store it.
struct ScanRequest: Identifiable, Hashable {
    let projectID: UUID
    let mode: ScanModeID
    /// Fixed when the request is made, so a capture screen that starts twice (SwiftUI may re-run
    /// `.task`) re-registers the same scan instead of adding an empty duplicate.
    var scanID = UUID()
    var id: UUID { scanID }
}
