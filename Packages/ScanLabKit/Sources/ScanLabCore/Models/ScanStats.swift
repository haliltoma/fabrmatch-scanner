public struct ScanStats: Codable, Sendable, Equatable {
    public var vertices: Int
    public var triangles: Int
    public var durationSec: Double

    public init(vertices: Int = 0, triangles: Int = 0, durationSec: Double = 0) {
        self.vertices = vertices
        self.triangles = triangles
        self.durationSec = durationSec
    }
}
