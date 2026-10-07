import SwiftUI

/// TrueDepth scanning: hold the phone so the front camera faces the part, 20–40 cm away, and move
/// around it slowly. The screen faces you, so you can follow the guidance while scanning.
struct TrueDepthScanView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void
    @Environment(AppModel.self) private var appModel
    @State private var model: TrueDepthModel?
    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                ARScanContainer(session: model.session).ignoresSafeArea()
                content(model)
            }
        }
        .onDisappear { model?.shutdown() }
        .task {
            guard model == nil else { return }
            let m = TrueDepthModel(request: request, store: appModel.store)
            model = m
            await m.prepare()
        }
        .statusBarHidden()
        .sensoryFeedback(.start, trigger: model?.phase == .recording)
        .sensoryFeedback(.success, trigger: model?.phase == .finished)
    }

    @ViewBuilder
    private func content(_ m: TrueDepthModel) -> some View {
        if case .failed(let message) = m.phase {
            CaptureFailureView(message: message) { onClose(nil) }
        } else {
            VStack {
                StatusCapsule(lines: ["\(m.status.keyframes) kare (\(m.status.depthFrames) derinlik)", "\(m.status.points.formatted(.number.notation(.compactName))) nokta",
                                      m.status.distance.map { "\(Int($0 * 100)) cm" } ?? "— cm"],
                              warning: m.guidance)
                    .padding(.top)
                Spacer()
                if m.phase == .ready {
                    Text("Ön kamerayı parçaya çevir, 20–40 cm uzaktan etrafında yavaşça dolaş.")
                        .font(.callout).multilineTextAlignment(.center)
                        .padding(12).background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
                ScanControls(phase: m.phase.scanPhase,
                             onRecord: { m.toggle() },
                             onFinish: { Task { onClose(await m.finish()) } },
                             onDiscard: { confirmDiscard = true })
                .confirmationDialog("Tarama silinsin mi?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Taramayı at", role: .destructive) {
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

extension TrueDepthModel.Phase {
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
