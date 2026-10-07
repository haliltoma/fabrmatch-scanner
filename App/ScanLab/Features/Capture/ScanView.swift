import SwiftUI
import ScanLabCore

/// Full-screen scanning UI (PRD §8 screen 2). Calls `onClose` with the project to open, or nil.
struct ScanView: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void

    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKeys.quality) private var quality = QualityProfile.balanced
    @AppStorage(SettingsKeys.maxRange) private var maxRange = 5.0
    @AppStorage(SettingsKeys.keepRawData) private var keepRawData = true
    @State private var model: ScanSessionModel?
    @State private var isConfirmingDiscard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = model?.mode?.session {
                ARScanContainer(session: session).ignoresSafeArea()
            }
            if let model {
                content(model)
            }
        }
        .onDisappear { model?.shutdown() }
        .task {
            guard model == nil else { return }
            let settings = CaptureSettings(quality: quality, maxRange: Float(maxRange), keepRawData: keepRawData)
            let model = ScanSessionModel(request: request, store: appModel.store, settings: settings)
            self.model = model
            await model.prepare()
        }
        .sensoryFeedback(.start, trigger: model?.phase == .scanning)
        .sensoryFeedback(.success, trigger: model?.phase == .finished)
        .statusBarHidden()
    }

    @ViewBuilder
    private func content(_ model: ScanSessionModel) -> some View {
        VStack {
            ScanHUD(elapsed: model.elapsed, triangles: model.triangleCount, thermal: model.thermal, warning: model.warning)
                .padding(.top)
            Spacer()
            if case .failed(let message) = model.phase {
                ContentUnavailableView("Tarama başlatılamadı", systemImage: "exclamationmark.triangle", description: Text(message))
                    .foregroundStyle(.white)
                Button("Kapat") { onClose(nil) }.buttonStyle(.borderedProminent)
            } else {
                ScanControls(phase: model.phase,
                             onRecord: { Task { await toggle(model) } },
                             onFinish: { Task { onClose(await model.finish()) } },
                             onDiscard: { isConfirmingDiscard = true })
                .confirmationDialog("Tarama silinsin mi?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                    Button("Taramayı at", role: .destructive) {
                        Task {
                            await model.discard()
                            onClose(nil)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func toggle(_ model: ScanSessionModel) async {
        if model.phase == .scanning {
            await model.pause()
        } else {
            await model.start()
        }
    }
}
