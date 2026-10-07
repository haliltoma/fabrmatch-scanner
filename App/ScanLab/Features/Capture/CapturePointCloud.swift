import Foundation
import ScanLabCore
import ScanLabExport

/// Fuses a recorded raw capture (`raw/capture/depth/*.sldf`) into a PLY point cloud (PRD M4, FR-4.7).
nonisolated enum CapturePointCloud {
    @discardableResult
    static func write(captureDirectory: URL, to url: URL, voxelSize: Float, depthRange: ClosedRange<Float> = 0.1...5) throws -> Int {
        let depthDir = captureDirectory.appendingPathComponent("depth")
        let files = try FileManager.default.contentsOfDirectory(at: depthDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sldf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var fuser = PointCloudFuser(voxelSize: voxelSize, minConfidence: 2, depthRange: depthRange)
        for file in files {
            fuser.add(try DepthFrameCodec.decode(Data(contentsOf: file)))
        }
        let mesh = fuser.mesh()
        try PLYBinaryExporter().export(mesh, to: url, options: ExportOptions(unit: .millimeters, upAxis: .y))
        return mesh.vertexCount
    }
}
