import SwiftUI

/// Bottom bar with large (≥ 48 pt, M20) record / finish / discard targets.
struct ScanControls: View {
    let phase: ScanPhase
    let onRecord: () -> Void
    let onFinish: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button("At", systemImage: "xmark", role: .destructive, action: onDiscard)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: .circle)
                .disabled(phase == .saving)

            Spacer()

            Button(action: onRecord) {
                Circle()
                    .fill(phase == .scanning ? .white : .red)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Image(systemName: phase == .scanning ? "pause.fill" : "record.circle")
                            .font(.title)
                            .foregroundStyle(phase == .scanning ? .black : .white)
                    }
            }
            .accessibilityLabel(phase == .scanning ? "Duraklat" : (phase == .paused ? "Devam et" : "Taramayı başlat"))
            .disabled(phase == .preparing || phase == .saving)

            Spacer()

            Button("Bitir", systemImage: "checkmark", action: onFinish)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: .circle)
                .disabled(phase != .scanning && phase != .paused)
        }
        .foregroundStyle(.white)
        .overlay {
            if phase == .saving { ProgressView("Kaydediliyor…").tint(.white) }
        }
    }
}
