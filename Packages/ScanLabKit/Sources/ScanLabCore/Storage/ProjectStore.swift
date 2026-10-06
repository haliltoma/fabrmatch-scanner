import Foundation

/// File-system project repository (M2, M17). All manifest writes are atomic (temp file + rename).
///
/// Layout under `root`: `Projects/<uuid>/…` for live projects, `Trash/<uuid>/…` for deleted ones.
public actor ProjectStore {
    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    public nonisolated let root: URL
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    public nonisolated var projectsDirectory: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    public nonisolated var trashDirectory: URL { root.appendingPathComponent("Trash", isDirectory: true) }

    public nonisolated func paths(for id: UUID, inTrash: Bool = false) -> ProjectPaths {
        ProjectPaths(root: (inTrash ? trashDirectory : projectsDirectory).appendingPathComponent(id.uuidString, isDirectory: true))
    }

    // MARK: Create / read / write

    public func createProject(name: String, tags: [String] = [], now: Date = .now) throws -> Project {
        let project = Project(name: try Self.validated(name), createdAt: now, tags: tags)
        let p = paths(for: project.id)
        for dir in [p.root, p.scans, p.assets, p.exports] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try save(project)
        return project
    }

    public func load(_ id: UUID) throws -> Project {
        let url = paths(for: id).manifest
        guard fileManager.fileExists(atPath: url.path) else { throw ProjectStoreError.notFound(id) }
        return try readManifest(at: url)
    }

    public func save(_ project: Project) throws {
        let p = paths(for: project.id, inTrash: project.deletedAt != nil)
        try fileManager.createDirectory(at: p.root, withIntermediateDirectories: true)
        try ProjectJSON.encoder().encode(project).write(to: p.manifest, options: .atomic)
    }

    /// Live projects, newest first. Unreadable manifests are skipped so one bad project can't hide the rest.
    public func listProjects() throws -> [ProjectSummary] {
        try summaries(in: projectsDirectory, inTrash: false).sorted { $0.project.createdAt > $1.project.createdAt }
    }

    public func listTrash() throws -> [ProjectSummary] {
        try summaries(in: trashDirectory, inTrash: true)
    }

    // MARK: Edit

    public func rename(_ id: UUID, to name: String) throws -> Project {
        var project = try load(id)
        project.name = try Self.validated(name)
        try save(project)
        return project
    }

    public func setTags(_ id: UUID, tags: [String]) throws -> Project {
        var project = try load(id)
        project.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        try save(project)
        return project
    }

    public func duplicate(_ id: UUID, now: Date = .now) throws -> Project {
        var copy = try load(id)
        copy.id = UUID()
        copy.name += " (kopya)"
        copy.createdAt = now.persistable
        try fileManager.copyItem(at: paths(for: id).root, to: paths(for: copy.id).root)
        try save(copy)
        return copy
    }

    /// Registers a scan and creates its folders; returns where the capture should write.
    public func addScan(_ record: ScanRecord, to projectID: UUID) throws -> ScanPaths {
        var project = try load(projectID)
        let scan = paths(for: projectID).scan(record.id)
        for dir in [scan.meshChunks, scan.frames] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        project.scans.removeAll { $0.id == record.id }
        project.scans.append(record)
        try save(project)
        try ProjectJSON.encoder().encode(record).write(to: scan.manifest, options: .atomic)
        return scan
    }

    public func updateScan(_ record: ScanRecord, in projectID: UUID) throws {
        var project = try load(projectID)
        guard let i = project.scans.firstIndex(where: { $0.id == record.id }) else { throw ProjectStoreError.notFound(record.id) }
        project.scans[i] = record
        try save(project)
        try ProjectJSON.encoder().encode(record).write(to: paths(for: projectID).scan(record.id).manifest, options: .atomic)
    }

    // MARK: Trash (FR-2.3, FR-17.4)

    public func moveToTrash(_ id: UUID, now: Date = .now) throws {
        var project = try load(id)
        project.deletedAt = now.persistable
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let destination = paths(for: id, inTrash: true).root
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: paths(for: id).root, to: destination)
        try save(project)
    }

    public func restore(_ id: UUID) throws -> Project {
        let source = paths(for: id, inTrash: true)
        guard fileManager.fileExists(atPath: source.manifest.path) else { throw ProjectStoreError.notFound(id) }
        var project = try readManifest(at: source.manifest)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        try fileManager.moveItem(at: source.root, to: paths(for: id).root)
        project.deletedAt = nil
        try save(project)
        return project
    }

    /// Permanently deletes trashed projects older than the retention period. Returns purged ids.
    @discardableResult
    public func purgeTrash(now: Date = .now, retention: TimeInterval = ProjectStore.trashRetention) throws -> [UUID] {
        var purged: [UUID] = []
        for summary in try listTrash() {
            guard let deletedAt = summary.project.deletedAt, now.timeIntervalSince(deletedAt) >= retention else { continue }
            try fileManager.removeItem(at: summary.paths.root)
            purged.append(summary.id)
        }
        return purged
    }

    // MARK: Storage (FR-2.6)

    public func storageSummary(for id: UUID) throws -> StorageSummary {
        let p = paths(for: id)
        let project = try load(id)
        let raw = project.scans.reduce(Int64(0)) { $0 + Self.directorySize(p.scan($1.id).raw) }
        let total = Self.directorySize(p.root)
        return StorageSummary(rawBytes: raw, processedBytes: total - raw, totalBytes: total)
    }

    /// "Ham veriyi temizle": removes raw frames/depth but keeps mesh chunks so the model still opens.
    public func clearRawFrames(for id: UUID) throws {
        let p = paths(for: id)
        for scan in try load(id).scans {
            let s = p.scan(scan.id)
            for dir in [s.frames, s.depth, s.confidence] where fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
            }
        }
    }

    // MARK: Helpers

    private func summaries(in directory: URL, inTrash: Bool) throws -> [ProjectSummary] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { dir in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            let p = paths(for: id, inTrash: inTrash)
            guard let project = try? readManifest(at: p.manifest) else { return nil }
            return ProjectSummary(project: project, paths: p, sizeBytes: Self.directorySize(p.root))
        }
    }

    private func readManifest(at url: URL) throws -> Project {
        try ProjectMigrator.migrate(ProjectJSON.decoder().decode(Project.self, from: Data(contentsOf: url)))
    }

    static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { throw ProjectStoreError.invalidName }
        return trimmed
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e {
            guard let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
