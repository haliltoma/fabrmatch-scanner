import Foundation
import ScanLabCore

struct ExportRequest: Identifiable {
    let projectName: String
    let scan: ScanRecord
    let chunks: URL
    let exports: URL
    var id: UUID { scan.id }
}
