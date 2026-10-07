import SwiftUI
import ScanLabCore

struct ProjectDetailView: View {
    let projectID: UUID
    @Environment(AppModel.self) private var appModel
    @State private var model: ProjectDetailModel?
    @State private var exporting: ExportRequest?
    @State private var viewing: ViewerRequest?
    @State private var sharing: SharedFile?
    @State private var previewing: SharedFile?

    var body: some View {
        Group {
            if let model, let project = model.project {
                List {
                    if let primary = model.primaryViewer(projectName: project.name) {
                        Section {
                            EmbeddedViewer(request: primary) { viewing = primary }
                                .listRowInsets(EdgeInsets())
                            Button("Tam ekranda aç (ölç, kırp, AR)", systemImage: "arrow.up.left.and.arrow.down.right") { viewing = primary }
                                .font(.headline)
                        } footer: {
                            Text("Döndürmek için sürükle, yakınlaştırmak için iki parmakla sıkıştır. Ölçüm ve AR için tam ekrana geç.")
                        }
                    }
                    ForEach(project.scans) { scan in
                        Section {
                            ScanRow(scan: scan, canExport: model.hasMesh(scan)) {
                                exporting = ExportRequest(baseName: project.name, source: .meshChunks(model.scanPaths(scan).meshChunks),
                                                          exports: model.exportsDirectory)
                            }
                            if model.hasMesh(scan) {
                                Button("3B görüntüle", systemImage: "cube") {
                                    viewing = model.viewer(.meshChunks(model.scanPaths(scan).meshChunks), title: project.name, scan: scan)
                                }
                            }
                            ForEach(model.outputs(of: scan), id: \.self) { file in
                                OutputRow(file: file, onView: {
                                    if file.pathExtension == "pdf" { previewing = SharedFile(url: file); return }
                                    viewing = model.viewer(.file(file), title: file.lastPathComponent, scan: scan)
                                }, onExport: {
                                    exporting = ExportRequest(baseName: file.deletingPathExtension().lastPathComponent, source: .file(file),
                                                              exports: model.exportsDirectory)
                                })
                            }
                            if model.photos(of: scan) != nil {
                                Button("Fotoğrafları paylaş (ZIP, Mac'te tam detay model)", systemImage: "photo.stack") {
                                    Task { sharing = await model.zipRawCapture(scan).map(SharedFile.init) }
                                }
                            } else if model.hasRawCapture(scan) {
                                Button("Ham kareleri paylaş (ZIP, Mac'te işlemek için)", systemImage: "shippingbox") {
                                    Task { sharing = await model.zipRawCapture(scan).map(SharedFile.init) }
                                }
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
                .modifier(ErrorAlert(model: model))
            } else {
                ProgressView()
            }
        }
        .sheet(item: $exporting, content: ExportView.init)
        .fullScreenCover(item: $viewing, onDismiss: { Task { await model?.load() } }, content: ViewerView.init)
        .sheet(item: $previewing) { file in QuickLookPreview(url: file.url).ignoresSafeArea() }
        .sheet(item: $sharing) { file in
            ShareSheet(url: file.url).presentationDetents([.medium, .large])
        }
        .task {
            let model = ProjectDetailModel(projectID: projectID, store: appModel.store)
            self.model = model
            await model.load()
        }
    }
}
