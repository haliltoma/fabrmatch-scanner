import SwiftUI

struct PhotoCaptureView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void
    @Environment(AppModel.self) private var appModel
    @State private var model: PhotoCaptureModel?
    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let m = model {
                ARScanContainer(session: m.session).ignoresSafeArea()
                if case .failed(let message) = m.phase {
                    CaptureFailureView(message: message) { onClose(nil) }
                } else {
                    VStack {
                        StatusCapsule(lines: ["\(m.frames) kare", "hedef 100–300"],
                                      warning: m.frames > 0 && m.frames < 60 && m.phase == .paused ? "Daha fazla açıdan çek" : nil)
                            .padding(.top)
                        Spacer()
                        ScanControls(phase: m.phase.scanPhase,
                                     onRecord: { m.toggle() },
                                     onFinish: { Task { onClose(await m.finish()) } },
                                     onDiscard: { confirmDiscard = true })
                        .confirmationDialog("Kayıt silinsin mi?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                            Button("Kaydı at", role: .destructive) {
                                Task {
                                    await m.discard()
                                    onClose(nil)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onDisappear { model?.shutdown() }
        .task {
            guard model == nil else { return }
            let m = PhotoCaptureModel(request: request, store: appModel.store)
            model = m
            await m.prepare()
        }
        .statusBarHidden()
    }
}

extension PhotoCaptureModel.Phase {
    var scanPhase: ScanPhase {
        switch self {
        case .preparing: .preparing
        case .ready: .ready
        case .recording: .scanning
        case .paused: .paused
        case .saving: .saving
        case .finished: .finished
        case .failed(let m): .failed(m)
        }
    }
}
