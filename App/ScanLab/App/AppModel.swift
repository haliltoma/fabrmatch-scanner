import Foundation
import Observation
import ScanLabCore

/// App-wide dependencies: project repository and detected device capabilities.
@Observable
final class AppModel {
    let store: ProjectStore
    private(set) var capabilities: Set<Capability> = []

    init(store: ProjectStore = ProjectStore(root: URL.documentsDirectory)) {
        self.store = store
    }

    func launch() async {
        capabilities = DeviceCapabilities.detect()
        #if DEBUG
        await DemoSeeder.seedIfRequested(store: store)
        #endif
        // Trash retention is enforced lazily at launch (FR-2.3).
        _ = try? await store.purgeTrash()
    }

    func availability(of mode: CaptureModeDescriptor) -> ModeAvailability {
        ModeAvailability(required: mode.requiredCapabilities, supported: capabilities)
    }
}
