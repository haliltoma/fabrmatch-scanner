#if DEBUG
import Foundation
import ScanLabCore
import ScanLabExport
import simd

/// DEBUG only: `-ScanLabSeedDemo YES` creates a demo project with a mesh scan and a point cloud,
/// so UI tests (and the simulator, which has no LiDAR) can exercise the project, viewer, crop and
/// export flows end to end.
enum DemoSeeder {
    static func seedIfRequested(store: ProjectStore) async {
        guard UserDefaults.standard.bool(forKey: "ScanLabSeedDemo") else { return }
        guard (try? await store.listProjects().contains { $0.project.name == "Demo parça" }) != true else { return }
        do {
            let project = try await store.createProject(name: "Demo parça", tags: ["demo"])
            var record = ScanRecord(mode: .lidarMesh, sensor: .lidar, createdAt: .now, device: "Simulator")
            let paths = try await store.addScan(record, to: project.id)
            let chunk = MeshChunk(id: UUID(), version: 1, transform: matrix_identity_float4x4,
                                  vertices: boxVertices(size: SIMD3(0.12, 0.06, 0.08)), indices: boxIndices,
                                  classifications: [UInt8](repeating: 4, count: 12))
            try MeshChunkCodec.encode(chunk).write(to: MeshStore.fileURL(for: chunk.id, in: paths.meshChunks))
            let cloud = (0..<4000).map { i -> SIMD3<Float> in
                let a = Float(i) * 0.37, h = Float(i % 40) / 40 * 0.06
                return SIMD3(cos(a) * 0.05, h, sin(a) * 0.05)
            }
            try PLYBinaryExporter().export(TriangleMesh(positions: cloud), to: paths.root.appendingPathComponent("pointcloud.ply"),
                                           options: ExportOptions(unit: .millimeters, upAxis: .y))
            record.stats = ScanStats(vertices: 8, triangles: 12, durationSec: 30)
            try await store.updateScan(record, in: project.id)
        } catch {
            print("Demo seed failed: \(error)")
        }
    }

    private static func boxVertices(size s: SIMD3<Float>) -> [SIMD3<Float>] {
        let h = s / 2
        return [SIMD3(-h.x, 0, -h.z), SIMD3(h.x, 0, -h.z), SIMD3(h.x, 0, h.z), SIMD3(-h.x, 0, h.z),
                SIMD3(-h.x, s.y, -h.z), SIMD3(h.x, s.y, -h.z), SIMD3(h.x, s.y, h.z), SIMD3(-h.x, s.y, h.z)]
    }

    private static let boxIndices: [UInt32] = [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1,
                                               1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0]
}
#endif
