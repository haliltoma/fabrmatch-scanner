import SwiftUI
import ScanLabCore

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: LibraryModel?
    @State private var path: [LibraryRoute] = []
    @State private var isShowingModePicker = false
    @State private var renaming: ProjectSummary?
    @State private var isShowingSettings = false
    @State private var activeScan: ScanRequest?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    LibraryList(model: model, renaming: $renaming)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Projeler")
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .project(let id): ProjectDetailView(projectID: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ayarlar", systemImage: "gearshape") { isShowingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Yeni tarama", systemImage: "plus") { isShowingModePicker = true }
                }
            }
            .sheet(isPresented: $isShowingModePicker) {
                ModePickerView { mode in
                    isShowingModePicker = false
                    Task { await startScan(mode) }
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(item: $renaming) { summary in
                RenameProjectView(initialName: summary.project.name) { newName in
                    Task { await model?.rename(summary.id, to: newName) }
                }
            }
            .fullScreenCover(item: $activeScan) { request in
                ScanContainer(request: request) { finishedProjectID in
                    activeScan = nil
                    Task {
                        await model?.reload()
                        if let finishedProjectID { path.append(.project(finishedProjectID)) }
                    }
                }
            }
        }
        .task {
            if model == nil { model = LibraryModel(store: appModel.store) }
            await model?.reload()
        }
    }

    private func startScan(_ mode: CaptureModeDescriptor) async {
        let name = "Tarama \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        guard let project = await model?.createProject(named: name) else { return }
        activeScan = ScanRequest(projectID: project.id, mode: mode.id)
    }
}

enum LibraryRoute: Hashable {
    case project(UUID)
}
