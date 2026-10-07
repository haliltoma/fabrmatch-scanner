public enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
    case obj
    case ply
    case stl
    case glb
    case xyz

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .obj: "OBJ"
        case .ply: "PLY (ikili)"
        case .stl: "STL (ikili)"
        case .glb: "GLB (glTF 2.0)"
        case .xyz: "XYZ (nokta listesi)"
        }
    }

    public var supportsColor: Bool { self == .ply }

    /// Formats that carry triangles; the others are point formats.
    public var needsFaces: Bool { self != .xyz && self != .ply }
    public var supportsPoints: Bool { self == .ply || self == .xyz || self == .glb }

    public var exporter: any MeshExporter {
        switch self {
        case .obj: OBJExporter()
        case .ply: PLYBinaryExporter()
        case .stl: STLBinaryExporter()
        case .glb: GLBExporter()
        case .xyz: XYZExporter()
        }
    }

    public var reader: any MeshReader {
        switch self {
        case .obj: OBJReader()
        case .ply: PLYBinaryReader()
        case .stl: STLBinaryReader()
        case .glb: GLBReader()
        case .xyz: XYZReader()
        }
    }
}
