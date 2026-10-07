import ModelIO
import ScanLabExport

/// Export targets offered in the app: the package's writers plus USDZ (SceneKit / Model I/O).
enum AppExportFormat: Hashable, Identifiable {
    case core(ExportFormat)
    case usdz

    var id: String { fileExtension }

    var fileExtension: String {
        switch self {
        case .core(let f): f.fileExtension
        case .usdz: "usdz"
        }
    }

    var title: String {
        switch self {
        case .core(let f): f.displayName
        case .usdz: "USDZ (AR, Apple)"
        }
    }

    /// Unit and axis apply to the package writers only (USDZ/Model I/O keep the source scale).
    var usesOptions: Bool { if case .core = self { return true } else { return false } }

    static func available(for content: ViewerContent) -> [AppExportFormat] {
        switch content {
        case .mesh: [.core(.stl), .core(.obj), .core(.ply), .core(.glb), .usdz]
        case .points: [.core(.ply), .core(.xyz), .core(.glb)]
        case .scene: ["obj", "stl", "ply"].filter { MDLAsset.canExportFileExtension($0) }
            .compactMap { ExportFormat(rawValue: $0).map(AppExportFormat.core) }
        }
    }
}
