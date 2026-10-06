import simd

public struct BoundingBox: Sendable, Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// Returns nil for an empty point set.
    public init?<S: Sequence>(points: S) where S.Element == SIMD3<Float> {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var lo = first, hi = first
        while let p = iterator.next() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        self.init(min: lo, max: hi)
    }

    public var size: SIMD3<Float> { max - min }
    public var center: SIMD3<Float> { (min + max) * 0.5 }

    public func isApproximatelyEqual(to other: BoundingBox, tolerance: Float) -> Bool {
        simd_reduce_max(simd_abs(min - other.min)) <= tolerance
            && simd_reduce_max(simd_abs(max - other.max)) <= tolerance
    }
}
