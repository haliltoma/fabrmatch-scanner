import RealityKit
import SwiftUI

struct ObjectCaptureScanView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void
    @Environment(AppModel.self) private var appModel
    @State private var model: ObjectCaptureModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let session = model.session, model.phase == .capturing || model.phase == .passComplete {
                    ObjectCaptureView(session: session).ignoresSafeArea()
                }
                overlay(model)
            }
        }
        .task {
            guard model == nil else { return }
            let m = ObjectCaptureModel(request: request, store: appModel.store)
            model = m
            await m.prepare()
        }
        .statusBarHidden()
        .sensoryFeedback(.success, trigger: model?.phase == .finished)
    }

    @ViewBuilder
    private func overlay(_ m: ObjectCaptureModel) -> some View {
        switch m.phase {
        case .failed(let message):
            CaptureFailureView(message: message) { onClose(m.projectID) }
        case .reconstructing(let fraction):
            VStack(spacing: 12) {
                ProgressView(value: fraction) { Text("Model oluşturuluyor…") }
                    .tint(.white)
                Text("Uygulamayı açık tut; birkaç dakika sürebilir.").font(.caption)
            }
            .foregroundStyle(.white)
            .padding(32)
        case .finished:
            VStack(spacing: 16) {
                Label("Model hazır", systemImage: "checkmark.seal.fill").font(.title2)
                Button("Projeyi aç") { onClose(m.projectID) }.buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        default:
            VStack {
                HStack {
                    Button("Vazgeç", role: .cancel) {
                        Task {
                            await m.discard()
                            onClose(nil)
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
                Spacer()
                if m.phase == .passComplete {
                    VStack(spacing: 10) {
                        Text("Tur tamamlandı").font(.headline)
                        Button("Ters çevirip devam et") { m.newPass(flipped: true) }.buttonStyle(.borderedProminent)
                        Button("Aynı konumda yeni tur") { m.newPass(flipped: false) }.buttonStyle(.bordered)
                        Button("Bitir ve model oluştur") { m.finishCapture() }.buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                } else if let action = m.primaryAction {
                    Button(action.title, action: action.run)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(.bottom)
        }
    }
}
