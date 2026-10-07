import Foundation
import simd

/// `transforms.json` in Nerfstudio's format for Gaussian-splat / NeRF training (PRD M7, FR-7.2).
/// ARKit cameras already use the OpenGL convention Nerfstudio expects (+Y up, looking down −Z),
/// so poses are written unchanged.
public struct NerfstudioTransforms: Codable, Sendable, Equatable {
    public struct Frame: Codable, Sendable, Equatable {
        public var filePath: String
        public var transformMatrix: [[Float]]

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case transformMatrix = "transform_matrix"
        }
    }

    public var cameraModel = "OPENCV"
    public var flX: Float, flY: Float, cx: Float, cy: Float
    public var w: Int, h: Int
    public var k1: Float = 0, k2: Float = 0, p1: Float = 0, p2: Float = 0
    public var frames: [Frame] = []

    enum CodingKeys: String, CodingKey {
        case cameraModel = "camera_model"
        case flX = "fl_x", flY = "fl_y", cx, cy, w, h, k1, k2, p1, p2, frames
    }

    public init(flX: Float, flY: Float, cx: Float, cy: Float, w: Int, h: Int) {
        self.flX = flX
        self.flY = flY
        self.cx = cx
        self.cy = cy
        self.w = w
        self.h = h
    }

    public mutating func append(filePath: String, pose: simd_float4x4) {
        // Row-major 4×4 as Nerfstudio expects.
        let rows = (0..<4).map { r in (0..<4).map { c in pose[c][r] } }
        frames.append(Frame(filePath: filePath, transformMatrix: rows))
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
}
