import simd

/// Fuses depth frames into one voxel-downsampled world-space point cloud (PRD M4).
/// Back-projection uses the ARKit camera convention documented on `DepthFrame`.
public struct PointCloudFuser: Sendable {
    public var voxelSize: Float
    public var minConfidence: UInt8
    public var depthRange: ClosedRange<Float>
    /// Upper bound on stored points (FR-4.6); beyond it new voxels are ignored.
    public var maxPoints: Int

    private var cells: [SIMD3<Int32>: Accumulator] = [:]

    struct Accumulator {
        var sum: SIMD3<Float>
        var count: Float
    }

    public init(voxelSize: Float, minConfidence: UInt8 = 2, depthRange: ClosedRange<Float> = 0.05...5, maxPoints: Int = 5_000_000) {
        precondition(voxelSize > 0)
        self.voxelSize = voxelSize
        self.minConfidence = minConfidence
        self.depthRange = depthRange
        self.maxPoints = maxPoints
    }

    public var pointCount: Int { cells.count }

    /// Adds every valid pixel; returns how many pixels contributed.
    @discardableResult
    public mutating func add(_ f: DepthFrame) -> Int {
        var used = 0
        for v in 0..<f.height {
            for u in 0..<f.width {
                let i = v * f.width + u
                let d = f.depth[i]
                guard d > 0, depthRange.contains(d), f.confidence[i] >= minConfidence else { continue }
                // Camera space (ARKit): +X right, +Y up, looking down −Z; pixel rows grow downward.
                let cam = SIMD4<Float>((Float(u) - f.cx) * d / f.fx, -(Float(v) - f.cy) * d / f.fy, -d, 1)
                let w = f.pose * cam
                let p = SIMD3(w.x, w.y, w.z)
                let key = SIMD3<Int32>((p / voxelSize).rounded(.down))
                if var acc = cells[key] {
                    acc.sum += p
                    acc.count += 1
                    cells[key] = acc
                } else if cells.count < maxPoints {
                    cells[key] = Accumulator(sum: p, count: 1)
                }
                used += 1
            }
        }
        return used
    }

    /// One point per occupied voxel (the mean of its samples), sorted for deterministic output.
    public func points() -> [SIMD3<Float>] {
        cells.sorted { a, b in
            (a.key.x, a.key.y, a.key.z) < (b.key.x, b.key.y, b.key.z)
        }.map { $0.value.sum / $0.value.count }
    }

    public func mesh() -> TriangleMesh { TriangleMesh(positions: points()) }
}
