import SwiftUI
import ScanLabCore

struct ProjectDetailView: View {
    let projectID: UUID
    @Environment(AppModel.self) private var appModel
    @State private var model: ProjectDetailModel?
    @State private var exporting: ExportRequest?

    var body: some View {
        Group {
            if let model, let project = model.project {
                List {
                    Section("Taramalar") {
                        ForEach(project.scans) { scan in
                            ScanRow(scan: scan) {
                                exporting = ExportRequest(projectName: project.name, scan: scan,
                                                          chunks: model.scanPaths(scan).meshChunks,
                                                          exports: model.exportsDirectory)
                            }
                        }
                    }
                    if let storage = model.storage {
                        Section("Depolama") {
                            LabeledContent("Toplam", value: storage.totalBytes.formatted(.byteCount(style: .file)))
                            LabeledContent("Ham veri", value: storage.rawBytes.formatted(.byteCount(style: .file)))
                            Button("Ham kareleri temizle", role: .destructive) {
                                Task { await model.clearRawFrames() }
                            }
                            .disabled(storage.rawBytes == 0)
                        }
                    }
                }
                .navigationTitle(project.name)
            } else {
                ProgressView()
            }
        }
        .sheet(item: $exporting, content: ExportView.init)
        .task {
            let model = ProjectDetailModel(projectID: projectID, store: appModel.store)
            self.model = model
            await model.load()
        }
    }
}
