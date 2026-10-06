/// Contract every capture module implements (PRD §4.3). Adding a mode means adding one conformer.
///
/// Main-actor isolated: implementations own an AR/AV session whose lifecycle is driven by the UI.
/// Heavy per-frame work must be handed off (e.g. to `MeshStore`) rather than done here.
@MainActor
public protocol CaptureMode: AnyObject {
    var id: ScanModeID { get }
    var displayName: String { get }
    var requiredCapabilities: Set<Capability> { get }
    var state: AsyncStream<CaptureState> { get }

    func prepare(settings: CaptureSettings) async throws
    func start() async throws
    func pause() async
    func finish() async throws -> ScanArtifact
    func cancel() async
}
