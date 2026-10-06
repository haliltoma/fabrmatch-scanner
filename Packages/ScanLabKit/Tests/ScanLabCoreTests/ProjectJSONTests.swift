import Foundation
import Testing
@testable import ScanLabCore

@Suite("project.json schema")
struct ProjectJSONTests {
    @Test("Decodes the PRD §5.2 example")
    func decodesPRDExample() throws {
        let json = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "name": "Salon",
          "createdAt": "2026-10-06T10:00:00Z",
          "tags": ["oda", "ev"],
          "scans": [{
            "id": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
            "mode": "lidar_mesh", "sensor": "lidar",
            "createdAt": "2026-10-06T10:05:00Z",
            "device": "iPhone 17 Pro Max",
            "stats": { "vertices": 1250000, "triangles": 2400000, "durationSec": 142 },
            "qualityProfile": "high",
            "transformToProject": [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
          }],
          "units": "meters",
          "schemaVersion": 1
        }
        """
        let project = try ProjectJSON.decoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.name == "Salon")
        let scan = try #require(project.scans.first)
        #expect(scan.mode == .lidarMesh)
        #expect(scan.sensor == .lidar)
        #expect(scan.stats.triangles == 2_400_000)
        #expect(scan.qualityProfile == .high)
        #expect(scan.containsFace == false)
    }

    @Test("Round-trips through the shared encoder")
    func roundTrip() throws {
        let original = Project(
            name: "Masa", createdAt: Date(timeIntervalSince1970: 1_800_000_000), tags: ["nesne"],
            scans: [ScanRecord(mode: .trueDepth, sensor: .trueDepth, createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                               device: "Test", selectionReason: "yakın", qualityScore: 0.8, containsFace: true)]
        )
        let data = try ProjectJSON.encoder().encode(original)
        #expect(try ProjectJSON.decoder().decode(Project.self, from: data) == original)
        #expect(String(decoding: data, as: UTF8.self).contains("\"truedepth\""))
    }

    @Test func rejectsNewerSchema() {
        let future = Project(name: "x", createdAt: .now, schemaVersion: Project.currentSchemaVersion + 1)
        #expect(throws: ProjectStoreError.unsupportedSchema(found: Project.currentSchemaVersion + 1, supported: Project.currentSchemaVersion)) {
            try ProjectMigrator.migrate(future)
        }
    }
}
