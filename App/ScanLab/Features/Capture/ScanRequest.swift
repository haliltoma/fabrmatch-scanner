import Foundation
import ScanLabCore

/// What the scan screen should capture and where to store it.
struct ScanRequest: Identifiable, Hashable {
    let projectID: UUID
    let mode: ScanModeID
    var id: UUID { projectID }
}
