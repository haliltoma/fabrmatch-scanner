import SceneKit
import SwiftUI
import ScanLabCore

/// 3D viewer (PRD M10) with display modes, fit, measurements (M11) and AR preview (M15).
struct ViewerView: View {
    let request: ViewerRequest
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.units) private var units = LengthUnit.meters
    @State private var model: ViewerModel
    @State private var scene: SCNScene?

    init(request: ViewerRequest) {
        self.request = request
        _model = State(initialValue: ViewerModel(request: request))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if let error = model.error {
                    ContentUnavailableView("Görüntülenemedi", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if model.content == nil {
                    ProgressView("Yükleniyor…")
                } else {
                    SceneViewContainer(model: model) { scene, view in
                        self.scene = scene
                        saveThumbnailIfMissing(view)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    bottomPanel
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $model.arPreview) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        }
        .task { await model.load() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Seçenekler", systemImage: "ellipsis.circle") {
                Button("Sığdır", systemImage: "arrow.up.left.and.arrow.down.right") { model.fit() }
                Button("AR'da gör", systemImage: "arkit") { model.prepareAR(scene: scene) }
                if case .file(let url) = request.source {
                    ShareLink(item: url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if model.cropping {
                CropPanel(model: model, canSave: request.outputDirectory != nil)
            }
            if let saved = model.savedCrop {
                Label("Kaydedildi: \(saved.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            }
            if model.measuring {
                Text(model.pendingPoint == nil ? "Ölçmek için ilk noktaya dokun" : "İkinci noktaya dokun")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !model.measurements.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.measurements) { m in
                            Text(format(meters: m.meters))
                                .font(.callout.monospacedDigit())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.yellow.opacity(0.25), in: .capsule)
                                .contextMenu { Button("Sil", systemImage: "trash", role: .destructive) { model.delete(m) } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack {
                if model.modes.count > 1 {
                    Picker("Görünüm", selection: $model.mode) {
                        ForEach(model.modes) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if model.canMeasure {
                    Toggle(isOn: $model.measuring) { Label("Ölç", systemImage: "ruler") }
                        .toggleStyle(.button)
                }
                Toggle(isOn: $model.showBox) { Label("Kutu", systemImage: "cube") }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Sınır kutusu")
                if model.canCrop {
                    Toggle(isOn: $model.cropping) { Label("Kırp", systemImage: "crop") }
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Kırp")
                }
            }
            if let info = statsLine { Text(info).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var statsLine: String? {
        guard let s = model.content?.summary else { return nil }
        var parts: [String] = []
        if s.triangles > 0 { parts.append("\(s.triangles.formatted()) üçgen") }
        if s.vertices > 0 && s.triangles == 0 { parts.append("\(s.vertices.formatted()) nokta") }
        if let size = s.size {
            parts.append([size.x, size.y, size.z].map { format(meters: $0, unit: false) }.joined(separator: " × ") + " \(units.symbol)")
        }
        return parts.joined(separator: " · ")
    }

    private func format(meters: Float, unit: Bool = true) -> String {
        let v = units.fromMeters(Double(meters))
        let digits = units == .meters ? 3 : (units == .millimeters ? 0 : 1)
        return v.formatted(.number.precision(.fractionLength(digits))) + (unit ? " \(units.symbol)" : "")
    }

    /// FR-2.1: the library shows a thumbnail; create it the first time a scan is viewed.
    private func saveThumbnailIfMissing(_ view: SCNView) {
        guard let url = request.thumbnailURL, !FileManager.default.fileExists(atPath: url.path) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))  // let the first frame render
            if let data = view.snapshot().jpegData(compressionQuality: 0.8) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
