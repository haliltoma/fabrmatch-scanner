import Foundation

/// `capture.json` next to the `depth/*.sldf` files (format "scanlab-capture" v1).
public struct CaptureManifest: Codable, Sendable, Equatable {
    public var format = "scanlab-capture"
    public var version = 1
    public var sensor: String
    public var frames: [String]

    public init(sensor: SensorKind, frames: [String]) {
        self.sensor = sensor == .trueDepth ? "truedepth" : "lidar"
        self.frames = frames
    }

    public static func frameName(_ index: Int) -> String {
        "depth/" + String(format: "%06d", index) + ".sldf"
    }
}
