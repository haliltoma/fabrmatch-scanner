import Foundation
import ScanLabCore

/// Something to convert and share: a LiDAR mesh, a point cloud or a model file (M13).
struct ExportRequest: Identifiable {
    let id = UUID()
    let baseName: String
    let source: ViewerRequest.Source
    let exports: URL
}
