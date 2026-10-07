import SwiftUI

struct RoomPlanScanView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void
    @Environment(AppModel.self) private var appModel
    @State private var model: RoomPlanModel?
    @State private var stopToken = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                switch model.phase {
                case .failed(let message):
                    CaptureFailureView(message: message) { onClose(nil) }
                case .preparing:
                    ProgressView().tint(.white)
                default:
                    RoomCaptureContainer(model: model, stopToken: $stopToken).ignoresSafeArea()
                    controls(model)
                }
            }
        }
        .task {
            let m = RoomPlanModel(request: request, store: appModel.store)
            model = m
            await m.prepare()
        }
        .statusBarHidden()
    }

    private func controls(_ m: RoomPlanModel) -> some View {
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
                if m.phase == .scanning {
                    Button("Bitti") {
                        m.stopRequested()
                        stopToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else if m.phase == .review {
                    Button("Kaydet") { Task { onClose(await m.save()) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            Spacer()
            if let summary = m.summary {
                Text(summary)
                    .font(.callout)
                    .padding(12)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                    .padding()
            } else if m.phase == .processing || m.phase == .saving {
                ProgressView(m.phase == .saving ? "Kaydediliyor…" : "Oda işleniyor…")
                    .padding(12).background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }
}
