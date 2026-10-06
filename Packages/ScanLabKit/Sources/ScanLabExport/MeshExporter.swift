import Foundation
import ScanLabCore

public protocol MeshExporter: Sendable {
    func export(_ mesh: TriangleMesh, to url: URL, options: ExportOptions) throws
}

public protocol MeshReader: Sendable {
    /// Returns geometry converted back into internal meters / Y-up using `options`.
    func read(from url: URL, options: ExportOptions) throws -> TriangleMesh
}

public enum MeshFormatError: Error, Equatable {
    case invalidHeader(String)
    case truncated
    case unsupported(String)
}
