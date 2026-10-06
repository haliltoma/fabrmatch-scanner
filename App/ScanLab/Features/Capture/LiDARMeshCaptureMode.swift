import ARKit
import ScanLabCore

enum CaptureError: LocalizedError {
    case unsupportedDevice
    case lowDiskSpace

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: "Bu cihaz LiDAR sahne yeniden yapılandırmasını desteklemiyor."
        case .lowDiskSpace: "Depolama alanı 1 GB'ın altında. Tarama öncesi yer aç."
        }
    }
}

/// M3: real-time LiDAR mesh capture with ARKit scene reconstruction.
final class LiDARMeshCaptureMode: CaptureMode {
    let id = ScanModeID.lidarMesh
    let displayName = "Oda / Ortam"
    let requiredCapabilities: Set<Capability> = [.lidarMesh, .sceneDepth]
    let state: AsyncStream<CaptureState>
    let session = ARSession()
    let store = MeshStore()

    private let stateContinuation: AsyncStream<CaptureState>.Continuation
    private let paths: ScanPaths
    private var record: ScanRecord
    private var settings = CaptureSettings()
    private var forwarder: MeshAnchorForwarder?
    private var hasRun = false
    private(set) var activeDuration: TimeInterval = 0
    private var runningSince: Date?

    init(paths: ScanPaths, record: ScanRecord, onStatus: @escaping @Sendable (FrameStatus) -> Void) {
        self.paths = paths
        self.record = record
        (state, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
        let interruptions = stateContinuation
        let forwarder = MeshAnchorForwarder(store: store, onStatus: onStatus) { interrupted in
            interruptions.yield(interrupted ? .warning(.relocalizing) : .scanning)
        }
        self.forwarder = forwarder
        session.delegate = forwarder
        session.delegateQueue = forwarder.queue
    }

    /// PRD M3 configuration block.
    static func makeConfiguration(worldMap: ARWorldMap? = nil) -> ARWorldTrackingConfiguration {
        let c = ARWorldTrackingConfiguration()
        c.sceneReconstruction = .meshWithClassification
        c.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        c.planeDetection = [.horizontal, .vertical]
        c.environmentTexturing = .none
        c.isAutoFocusEnabled = true
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            c.videoFormat = format
        }
        c.initialWorldMap = worldMap
        return c
    }

    func prepare(settings: CaptureSettings) async throws {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            throw CaptureError.unsupportedDevice
        }
        if let free = try? DiskSpace.availableBytes(at: paths.root), DiskSpace.isLow(availableBytes: free) {
            throw CaptureError.lowDiskSpace
        }
        self.settings = settings
        record.qualityProfile = settings.quality
        forwarder?.setMaxRange(settings.maxRange)
        stateContinuation.yield(.ready)
    }

    func start() async throws {
        if hasRun {
            // FR-3.1: resume from the saved world map so new geometry lines up with the old.
            let map = try? loadWorldMap()
            session.run(Self.makeConfiguration(worldMap: map))
        } else {
            session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
            hasRun = true
        }
        runningSince = .now
        stateContinuation.yield(.scanning)
    }

    func pause() async {
        accumulateDuration()
        await saveWorldMap()
        session.pause()
        _ = try? await autosave()
        stateContinuation.yield(.paused)
    }

    /// Writes changed chunks to `raw/mesh_chunks` (PRD §5.3 periodic autosave).
    @discardableResult
    func autosave() async throws -> Int {
        try await store.flush(to: paths.meshChunks)
    }

    func finish() async throws -> ScanArtifact {
        accumulateDuration()
        await saveWorldMap()
        session.pause()
        try await autosave()
        let stats = await store.stats
        record.stats = ScanStats(vertices: stats.vertexCount, triangles: stats.triangleCount, durationSec: activeDuration.rounded())
        if !settings.keepRawData {
            try? FileManager.default.removeItem(at: paths.frames)
        }
        let files = await store.snapshot().map { MeshStore.fileURL(for: $0.id, in: paths.meshChunks) }
        stateContinuation.yield(.finished)
        stateContinuation.finish()
        return ScanArtifact(record: record, scanDirectory: paths.root, chunkFiles: files, framesDirectory: settings.keepRawData ? paths.frames : nil)
    }

    func cancel() async {
        session.pause()
        await store.removeAll()
        stateContinuation.yield(.idle)
        stateContinuation.finish()
    }

    private func accumulateDuration() {
        if let since = runningSince { activeDuration += Date.now.timeIntervalSince(since) }
        runningSince = nil
    }

    private func saveWorldMap() async {
        // Async import of getCurrentWorldMap: its completion runs on an ARKit queue, so a
        // main-actor closure there would trip Swift 6 isolation checks.
        guard let map = try? await session.currentWorldMap(),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else { return }
        try? data.write(to: paths.worldMap, options: .atomic)
    }

    private func loadWorldMap() throws -> ARWorldMap? {
        let data = try Data(contentsOf: paths.worldMap)
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }
}
