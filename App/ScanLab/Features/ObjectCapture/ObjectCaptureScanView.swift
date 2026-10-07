import RealityKit
import SwiftUI

struct ObjectCaptureScanView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void
    @Environment(AppModel.self) private var appModel
    @State private var model: ObjectCaptureModel?
    @State private var confirmFinish = false

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
            VStack(spacing: 12) {
                HStack {
                    Button("Vazgeç", role: .cancel) {
                        Task {
                            await m.discard()
                            onClose(nil)
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if m.phase == .capturing || m.phase == .passComplete, m.shots > 0 {
                        Text("Tur \(min(m.completedPasses + 1, ObjectCaptureModel.recommendedPasses))/\(ObjectCaptureModel.recommendedPasses) · \(m.shots) foto")
                            .font(.subheadline.monospacedDigit())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                }
                .padding()
                if let message = m.feedback.first?.message, m.phase == .capturing {
                    Text(message)
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.yellow.opacity(0.9), in: .capsule)
                        .foregroundStyle(.black)
                        .transition(.opacity)
                }
                Spacer()
                if m.phase == .passComplete {
                    passComplete(m)
                } else if let action = m.primaryAction {
                    if m.session?.state == .ready { ObjectCaptureTipsCard() }
                    Button(action.title, action: action.run)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .animation(.default, value: m.feedback.first?.message)
            .padding(.bottom)
            .confirmationDialog("Model eksik çıkabilir", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Yine de bitir") { m.finishCapture() }
                Button("Taramaya devam et", role: .cancel) {}
            } message: {
                Text(m.finishWarning ?? "")
            }
        }
    }

    private func passComplete(_ m: ObjectCaptureModel) -> some View {
        VStack(spacing: 10) {
            Text("Tur \(m.completedPasses) tamamlandı").font(.headline)
            Text(nextPassHint(m)).font(.footnote).multilineTextAlignment(.center)
            if m.completedPasses < ObjectCaptureModel.recommendedPasses {
                Button("Yeni tur (farklı yükseklik)") { m.newPass(flipped: false) }.buttonStyle(.borderedProminent)
                Button("Ters çevirip devam et") { m.newPass(flipped: true) }.buttonStyle(.bordered)
            } else {
                Button("Ters çevirip alt yüzü çek") { m.newPass(flipped: true) }.buttonStyle(.borderedProminent)
                Button("Aynı konumda yeni tur") { m.newPass(flipped: false) }.buttonStyle(.bordered)
            }
            Button("Bitir ve model oluştur") {
                if m.finishWarning == nil { m.finishCapture() } else { confirmFinish = true }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func nextPassHint(_ m: ObjectCaptureModel) -> String {
        switch m.completedPasses {
        case 1: "Şimdi telefonu alçaltıp nesneye yandan, masa hizasına yakın bakarak bir tur daha at."
        case 2: "Son tur: telefonu yükseltip nesneye yukarıdan, 45° açıyla bak."
        default: "Alt yüzü de istiyorsan nesneyi yan yatır veya ters çevir; yoksa modeli oluşturabilirsin."
        }
    }
}
