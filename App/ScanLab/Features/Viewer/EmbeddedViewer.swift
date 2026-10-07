import SwiftUI

/// The project's model, live and rotatable, at the top of the project screen — the first thing
/// you see after a scan (like the scan-detail screens of Polycam or Scaniverse).
struct EmbeddedViewer: View {
    let request: ViewerRequest
    let onExpand: () -> Void
    @State private var model: ViewerModel

    init(request: ViewerRequest, onExpand: @escaping () -> Void) {
        self.request = request
        self.onExpand = onExpand
        _model = State(initialValue: ViewerModel(request: request))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let error = model.error {
                ContentUnavailableView("Görüntülenemedi", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.content == nil {
                ProgressView("3B model yükleniyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SceneViewContainer(model: model) { _, view in
                    saveThumbnailIfMissing(view)
                }
            }
            // .borderless: inside a List row a default-style button becomes the row's action, and the
            // SCNView's gesture recognizers then swallow the tap (found by the UI tests).
            Button("Tam ekran", systemImage: "arrow.up.left.and.arrow.down.right", action: onExpand)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .font(.title3)
                .padding(10)
                .background(.regularMaterial, in: .circle)
                .padding(12)
        }
        .frame(height: 340)
        .background(Color(.secondarySystemBackground))
        .task { await model.load() }
    }

    private func saveThumbnailIfMissing(_ view: SceneKitViewSnapshotting) {
        guard let url = request.thumbnailURL, !FileManager.default.fileExists(atPath: url.path) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if let data = view.snapshot().jpegData(compressionQuality: 0.8) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
