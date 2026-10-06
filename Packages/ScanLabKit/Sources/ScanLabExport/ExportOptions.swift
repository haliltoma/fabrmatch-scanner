import ScanLabCore

public enum UpAxis: String, Sendable, CaseIterable, Codable {
    /// ARKit / glTF / USD convention.
    case y
    /// CAD and most slicers.
    case z
}

/// User-facing export settings (FR-13.1). Geometry is converted from meters into `unit`.
public struct ExportOptions: Sendable, Equatable {
    public var unit: LengthUnit
    public var upAxis: UpAxis
    public var includeColors: Bool

    public init(unit: LengthUnit = .meters, upAxis: UpAxis = .y, includeColors: Bool = true) {
        self.unit = unit
        self.upAxis = upAxis
        self.includeColors = includeColors
    }

    /// Maps an internal (meters, Y-up) point to file space.
    public func transform(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let s = Float(1 / unit.metersPerUnit)
        let q = p * s
        switch upAxis {
        case .y: return q
        case .z: return SIMD3(q.x, -q.z, q.y)
        }
    }

    /// Inverse of `transform`, used by readers during round-trip verification.
    public func inverseTransform(_ q: SIMD3<Float>) -> SIMD3<Float> {
        let p: SIMD3<Float>
        switch upAxis {
        case .y: p = q
        case .z: p = SIMD3(q.x, q.z, -q.y)
        }
        return p * Float(unit.metersPerUnit)
    }
}
