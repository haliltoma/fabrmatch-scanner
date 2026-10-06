import Foundation
import Observation
import ScanLabCore

/// State and actions for the project library (M2).
@Observable
final class LibraryModel {
    private let store: ProjectStore
    private(set) var projects: [ProjectSummary] = []
    var searchText = ""
    var sortOrder: LibrarySortOrder = .newest
    var errorMessage: String?

    init(store: ProjectStore) {
        self.store = store
    }

    /// FR-2.2: search by name or tag, then sort.
    var visibleProjects: [ProjectSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? projects : projects.filter { summary in
            summary.project.name.localizedStandardContains(query)
                || summary.project.tags.contains { $0.localizedStandardContains(query) }
        }
        return sortOrder.sorted(filtered)
    }

    func reload() async {
        await perform { projects = try await store.listProjects() }
    }

    func createProject(named name: String) async -> Project? {
        var created: Project?
        await perform {
            created = try await store.createProject(name: name)
            projects = try await store.listProjects()
        }
        return created
    }

    func rename(_ id: UUID, to name: String) async {
        await perform {
            _ = try await store.rename(id, to: name)
            projects = try await store.listProjects()
        }
    }

    func duplicate(_ id: UUID) async {
        await perform {
            _ = try await store.duplicate(id)
            projects = try await store.listProjects()
        }
    }

    func moveToTrash(_ ids: some Sequence<UUID>) async {
        await perform {
            for id in ids { try await store.moveToTrash(id) }
            projects = try await store.listProjects()
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
