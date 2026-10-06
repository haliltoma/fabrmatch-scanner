import SwiftUI
import ScanLabCore

struct ModePickerRow: View {
    let mode: CaptureModeDescriptor
    let availability: ModeAvailability

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.headline)
                Text(mode.subtitle).font(.subheadline).foregroundStyle(.secondary)
                if let reason = availability.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                } else if let phase = mode.plannedPhase {
                    Text("Yakında (\(phase))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
