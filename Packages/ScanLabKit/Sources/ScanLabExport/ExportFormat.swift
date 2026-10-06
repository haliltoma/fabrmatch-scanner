public enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
    case obj
    case ply
    case stl

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .obj: "OBJ"
        case .ply: "PLY (ikili)"
        case .stl: "STL (ikili)"
        }
    }

    public var supportsColor: Bool { self == .ply }

    public var exporter: any MeshExporter {
        switch self {
        case .obj: OBJExporter()
        case .ply: PLYBinaryExporter()
        case .stl: STLBinaryExporter()
        }
    }

    public var reader: any MeshReader {
        switch self {
        case .obj: OBJReader()
        case .ply: PLYBinaryReader()
        case .stl: STLBinaryReader()
        }
    }
}
