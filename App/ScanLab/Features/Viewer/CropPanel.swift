import SwiftUI

/// Crop controls (FR-9.9): lower/upper handle per axis, preview on release, save as a new file.
struct CropPanel: View {
    @Bindable var model: ViewerModel
    let canSave: Bool

    var body: some View {
        VStack(spacing: 6) {
            axis("Genişlik (X)", \.x)
            axis("Yükseklik (Y)", \.y)
            axis("Derinlik (Z)", \.z)
            HStack {
                Button("Sıfırla", role: .destructive) { model.resetCrop() }
                Spacer()
                if canSave {
                    Button("Kırpılmışı kaydet", systemImage: "square.and.arrow.down") { Task { await model.saveCrop() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4)
        }
    }

    private func axis(_ title: String, _ key: WritableKeyPath<SIMD3<Double>, Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 92, alignment: .leading)
            // Handles may cross; MeshCropper.box orders them, so no clamping is needed here.
            Slider(value: $model.cropLower[dynamicMember: key], in: 0...1) { editing in if !editing { Task { await model.applyCropPreview() } } }
                .accessibilityLabel("\(title) alt sınır")
            Slider(value: $model.cropUpper[dynamicMember: key], in: 0...1) { editing in if !editing { Task { await model.applyCropPreview() } } }
                .accessibilityLabel("\(title) üst sınır")
        }
    }
}
