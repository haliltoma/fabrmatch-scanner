import Foundation
import Testing
@testable import ScanLabCore

@Suite struct ProjectStoreTests {
    @Test("Creates the PRD §5.1 folder layout")
    func createsLayout() async throws {
        let tmp = try TemporaryDirectory()
        let store = ProjectStore(root: tmp.url)
        let project = try await store.createProject(name: "  Salon  ", tags: ["oda"])
        #expect(project.name == "Salon")
        let p = store.paths(for: project.id)
        for url in [p.manifest, p.scans, p.assets, p.exports] {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(try await store.load(project.id) == project)
    }

    @Test("Rejects empty names", arguments: ["", "   ", "\n"])
    func rejectsEmptyName(name: String) async throws {
        let tmp = try TemporaryDirectory()
        await #expect(throws: ProjectStoreError.invalidName) { try await ProjectStore(root: tmp.url).createProject(name: name) }
    }

    @Test func listsNewestFirstAndSkipsCorruptManifests() async throws {
        let tmp = try TemporaryDirectory()
        let store = ProjectStore(root: tmp.url)
        let old = try await store.createProject(name: "Eski", now: Date(timeIntervalSince1970: 1))
        let new = try await store.createProject(name: "Yeni", now: Date(timeIntervalSince1970: 2))
        let broken = try await store.createProject(name: "Bozuk")
        try Data("{".utf8).write(to: store.paths(for: broken.id).manifest)
        #expect(try await store.listProjects().map(\.id) == [new.id, old.id])
    }

    @Test func renameTagsDuplicate() async throws {
        let tmp = try TemporaryDirectory()
        let store = ProjectStore(root: tmp.url)
        let project = try await store.createProject(name: "A")
        #expect(try await store.rename(project.id, to: "B").name == "B")
        #expect(try await store.setTags(project.id, tags: ["ev", " ev ", "", "oda"]).tags == ["ev", "oda"])
        let copy = try await store.duplicate(project.id)
        #expect(copy.id != project.id)
        #expect(copy.name == "B (kopya)")
        #expect(try await store.listProjects().count == 2)
    }

    @Test("Trash keeps projects 30 days, then purges (FR-2.3)")
    func trashLifecycle() async throws {
        let tmp = try TemporaryDirectory()
        let store = ProjectStore(root: tmp.url)
        let day: TimeInterval = 86_400
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let keep = try await store.createProject(name: "Geri al")
        let purge = try await store.createProject(name: "Sil")

        try await store.moveToTrash(keep.id, now: t0)
        try await store.moveToTrash(purge.id, now: t0)
        #expect(try await store.listProjects().isEmpty)
        #expect(try await store.purgeTrash(now: t0.addingTimeInterval(29 * day)).isEmpty)

        let restored = try await store.restore(keep.id)
        #expect(restored.deletedAt == nil)
        #expect(try await store.purgeTrash(now: t0.addingTimeInterval(30 * day)) == [purge.id])
        #expect(try await store.listTrash().isEmpty)
        #expect(try await store.listProjects().map(\.id) == [keep.id])
    }

    @Test("Scans register in the manifest and raw data can be cleared (FR-2.6)")
    func scansAndStorage() async throws {
        let tmp = try TemporaryDirectory()
        let store = ProjectStore(root: tmp.url)
        let project = try await store.createProject(name: "P")
        var record = ScanRecord(mode: .lidarMesh, sensor: .lidar, createdAt: .now, device: "Test")
        let scan = try await store.addScan(record, to: project.id)
        try Data(count: 50_000).write(to: scan.frames.appendingPathComponent("0001.heic"))
        try Data(count: 10_000).write(to: scan.meshChunks.appendingPathComponent("a.bin"))

        let summary = try await store.storageSummary(for: project.id)
        #expect(summary.rawBytes >= 60_000)
        #expect(summary.totalBytes >= summary.rawBytes)

        record.stats.triangles = 7
        try await store.updateScan(record, in: project.id)
        #expect(try await store.load(project.id).scans.first?.stats.triangles == 7)

        try await store.clearRawFrames(for: project.id)
        #expect(!FileManager.default.fileExists(atPath: scan.frames.path))
        #expect(FileManager.default.fileExists(atPath: scan.meshChunks.appendingPathComponent("a.bin").path))
    }

    @Test func lowDiskThreshold() {
        #expect(DiskSpace.isLow(availableBytes: 999_999_999))
        #expect(!DiskSpace.isLow(availableBytes: 2_000_000_000))
    }
}
