import SwiftUI
import ScanLabCore

struct ProjectDetailView: View {
    let projectID: UUID
    @Environment(AppModel.self) private var appModel
    @State private var model: ProjectDetailModel?
    @State private var exporting: ExportRequest?
    @State private var viewing: ViewerRequest?
    @State private var sharing: SharedFile?

    var body: some View {
        Group {
            if let model, let project = model.project {
                List {
                    ForEach(project.scans) { scan in
                        Section {
                            ScanRow(scan: scan, canExport: model.hasMesh(scan)) {
                                exporting = ExportRequest(projectName: project.name, scan: scan,
                                                          chunks: model.scanPaths(scan).meshChunks,
                                                          exports: model.exportsDirectory)
                            }
                            .contentShape(.rect)
                            .onTapGesture { viewing = model.defaultViewer(for: scan, projectName: project.name) }
                            if model.hasMesh(scan) {
                                Button("3B görüntüle", systemImage: "cube") {
                                    viewing = model.viewer(.meshChunks(model.scanPaths(scan).meshChunks), title: project.name)
                                }
                            }
                            ForEach(model.outputs(of: scan), id: \.self) { file in
                                OutputRow(file: file) {
                                    viewing = model.viewer(.file(file), title: file.lastPathComponent)
                                }
                            }
                            if model.hasRawCapture(scan) {
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
                .alert("Hata", isPresented: Binding(isPresent: Binding(get: { model.errorMessage }, set: { model.errorMessage = $0 }))) {
                } message: {
                    Text(model.errorMessage ?? "")
                }
            } else {
                ProgressView()
            }
        }
        .sheet(item: $exporting, content: ExportView.init)
        .fullScreenCover(item: $viewing, content: ViewerView.init)
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

/// One deliverable of a scan: open it in the viewer when possible, always shareable.
private struct OutputRow: View {
    let file: URL
    let onView: () -> Void

    private var viewable: Bool { ["usdz", "ply", "stl", "obj"].contains(file.pathExtension.lowercased()) }

    var body: some View {
        HStack {
            Label(file.lastPathComponent, systemImage: viewable ? "cube.transparent" : "doc.text")
                .font(.subheadline)
            Spacer()
            if viewable {
                Button("Görüntüle", action: onView).buttonStyle(.borderless)
            }
            ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Paylaş")
        }
    }
}

struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
