import Foundation

/// Writes SLDF frames and the `capture.json` manifest off the ARKit thread (PRD §4.4).
/// Frames are written immediately (crash-safe); the manifest is rewritten on every `flush`.
public actor CaptureWriter {
    public let directory: URL
    private let sensor: SensorKind
    private var names: [String] = []

    public init(directory: URL, sensor: SensorKind) {
        self.directory = directory
        self.sensor = sensor
    }

    public var frameCount: Int { names.count }

    public func append(_ frame: DepthFrame) throws {
        let name = CaptureManifest.frameName(names.count + 1)
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DepthFrameCodec.encode(frame).write(to: url, options: .atomic)
        names.append(name)
    }

    /// Writes the manifest listing every frame so far. Call periodically and at the end.
    public func flush() throws {
        guard !names.isEmpty else { return }
        let data = try JSONEncoder().encode(CaptureManifest(sensor: sensor, frames: names))
        try data.write(to: directory.appendingPathComponent("capture.json"), options: .atomic)
    }
}
