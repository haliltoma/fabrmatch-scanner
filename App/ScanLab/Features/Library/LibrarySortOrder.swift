import ScanLabCore

/// FR-2.2 sort options.
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case newest, name, size

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: "Tarih"
        case .name: "Ad"
        case .size: "Boyut"
        }
    }

    func sorted(_ items: [ProjectSummary]) -> [ProjectSummary] {
        switch self {
        case .newest: items.sorted { $0.project.createdAt > $1.project.createdAt }
        case .name: items.sorted { $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
        case .size: items.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }
}
