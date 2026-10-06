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
                Section("Biçim") {
                    Picker("Format", selection: $model.format) {
                        ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Birim", selection: $model.unit) {
                        ForEach(LengthUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                    }
                    Picker("Yukarı ekseni", selection: $model.upAxis) {
                        Text("Y (ARKit, glTF)").tag(UpAxis.y)
                        Text("Z (CAD, dilimleyici)").tag(UpAxis.z)
                    }
                }
                Section {
                    Button {
                        Task { await model.export() }
                    } label: {
                        if model.isExporting {
                            ProgressView()
                        } else {
                            Text("Dışa aktar")
                        }
                    }
                    .disabled(model.isExporting)
                }
                if let result = model.result {
                    Section("Sonuç") {
                        LabeledContent("Üçgen", value: result.triangles.formatted())
                        Label(result.verified ? "Doğrulandı (sayı + sınır kutusu)" : "Doğrulama başarısız",
                              systemImage: result.verified ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(result.verified ? .green : .orange)
                        ShareLink(item: result.url) {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
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
    }
}
