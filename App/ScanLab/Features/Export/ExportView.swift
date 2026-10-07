import SwiftUI
import ScanLabCore
import ScanLabExport

struct ExportView: View {
    @State private var model: ExportModel
    @Environment(\.dismiss) private var dismiss

    init(request: ExportRequest) {
        _model = State(initialValue: ExportModel(request: request))
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.content == nil, model.errorMessage == nil {
                    ProgressView("Hazırlanıyor…")
                } else {
                    Section("Biçim") {
                        Picker("Format", selection: $model.format) {
                            ForEach(model.formats) { Text($0.title).tag($0) }
                        }
                        if model.format.usesOptions {
                            Picker("Birim", selection: $model.unit) {
                                ForEach(LengthUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                            }
                            Picker("Yukarı ekseni", selection: $model.upAxis) {
                                Text("Y (ARKit, glTF, Blender)").tag(UpAxis.y)
                                Text("Z (CAD, dilimleyici)").tag(UpAxis.z)
                            }
                        }
                    }
                    Section {
                        Button {
                            Task { await model.export() }
                        } label: {
                            if model.isExporting { ProgressView() } else { Text("Dışa aktar") }
                        }
                        .disabled(model.isExporting || model.formats.isEmpty)
                        .accessibilityIdentifier("export.run")
                    }
                    if let result = model.result {
                        Section("Sonuç") {
                            LabeledContent("İçerik", value: result.summary)
                            Label(result.verified ? "Doğrulandı (yeniden okundu)" : "Doğrulama başarısız",
                                  systemImage: result.verified ? "checkmark.seal" : "exclamationmark.triangle")
                                .foregroundStyle(result.verified ? .green : .orange)
                            ShareLink(item: result.url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            }
            .navigationTitle("Dışa aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .alert("Dışa aktarma hatası", isPresented: Binding(isPresent: $model.errorMessage)) {} message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task { await model.load() }
    }
}
