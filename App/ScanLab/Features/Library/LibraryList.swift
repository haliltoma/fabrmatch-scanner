import SwiftUI
import ScanLabCore

struct LibraryList: View {
    @Bindable var model: LibraryModel
    @Binding var renaming: ProjectSummary?
    @State private var selection: Set<UUID> = []
    @Environment(\.editMode) private var editMode

    var body: some View {
        List(selection: $selection) {
            ForEach(model.visibleProjects) { summary in
                NavigationLink(value: LibraryRoute.project(summary.id)) {
                    ProjectRow(summary: summary)
                }
                .contextMenu {
                    Button("Yeniden adlandır", systemImage: "pencil") { renaming = summary }
                    Button("Çoğalt", systemImage: "plus.square.on.square") {
                        Task { await model.duplicate(summary.id) }
                    }
                    Button("Çöp kutusuna taşı", systemImage: "trash", role: .destructive) {
                        Task { await model.moveToTrash([summary.id]) }
                    }
                }
                .swipeActions {
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        Task { await model.moveToTrash([summary.id]) }
                    }
                }
            }
        }
        .overlay {
            if model.visibleProjects.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "Henüz proje yok" : "Sonuç yok",
                    systemImage: "cube.transparent",
                    description: Text(model.searchText.isEmpty ? "Yeni bir tarama başlatmak için + simgesine dokun." : "Farklı bir ad veya etiket dene.")
                )
            }
        }
        .searchable(text: $model.searchText, prompt: "Ad veya etiket")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Sırala", systemImage: "arrow.up.arrow.down") {
                    Picker("Sırala", selection: $model.sortOrder) {
                        ForEach(LibrarySortOrder.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .bottomBar) {
                if editMode?.wrappedValue.isEditing == true, !selection.isEmpty {
                    Button("Seçilenleri sil (\(selection.count))", systemImage: "trash", role: .destructive) {
                        let ids = selection
                        selection.removeAll()
                        Task { await model.moveToTrash(ids) }
                    }
                }
            }
        }
        .refreshable { await model.reload() }
        .alert("Hata", isPresented: Binding(isPresent: $model.errorMessage)) {} message: {
            Text(model.errorMessage ?? "")
        }
    }
}
