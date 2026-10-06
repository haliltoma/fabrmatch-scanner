import Foundation
import Observation
import ScanLabCore

@Observable
final class ProjectDetailModel {
    let projectID: UUID
    private let store: ProjectStore
    private(set) var project: Project?
    private(set) var storage: StorageSummary?
    var errorMessage: String?

    init(projectID: UUID, store: ProjectStore) {
        self.projectID = projectID
        self.store = store
    }

    func load() async {
        do {
            project = try await store.load(projectID)
            storage = try await store.storageSummary(for: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearRawFrames() async {
        do {
            try await store.clearRawFrames(for: projectID)
            storage = try await store.storageSummary(for: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanPaths(_ scan: ScanRecord) -> ScanPaths {
        store.paths(for: projectID).scan(scan.id)
    }

    var exportsDirectory: URL { store.paths(for: projectID).exports }
}
