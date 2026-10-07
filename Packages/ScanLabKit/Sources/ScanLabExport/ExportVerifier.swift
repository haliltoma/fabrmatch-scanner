import Foundation
import ScanLabCore
import simd

public struct ExportVerification: Sendable, Equatable {
    public var expectedTriangles: Int
    public var actualTriangles: Int
    public var boundsMatch: Bool

    public var passed: Bool { expectedTriangles == actualTriangles && boundsMatch }
}

/// FR-13.5: re-open the exported file and compare triangle count and bounding box.
public enum ExportVerifier {
    public static func verify(
        _ mesh: TriangleMesh, exportedTo url: URL, format: ExportFormat, options: ExportOptions,
        tolerance: Float = 1e-4
    ) throws -> ExportVerification {
        let reread = try format.reader.read(from: url, options: options)
        let boundsMatch: Bool = switch (mesh.bounds, reread.bounds) {
        case let (a?, b?): a.isApproximatelyEqual(to: b, tolerance: tolerance * max(1, simd_reduce_max(a.size)))
        case (nil, nil): true
        default: false
        }
        // Point formats (XYZ) carry no faces by design.
        let expected = format == .xyz ? 0 : mesh.triangleCount
        return ExportVerification(expectedTriangles: expected, actualTriangles: reread.triangleCount, boundsMatch: boundsMatch)
    }
}
