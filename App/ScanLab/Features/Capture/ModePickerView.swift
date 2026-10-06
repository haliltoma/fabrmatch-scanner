import SwiftUI
import ScanLabCore

/// PRD §8 screen 1: mode selection; unsupported or not-yet-built modes are disabled with a reason (FR-1.2).
struct ModePickerView: View {
    let onSelect: (CaptureModeDescriptor) -> Void
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(CaptureModeDescriptor.all) { mode in
                let availability = appModel.availability(of: mode)
                Button { onSelect(mode) } label: {
                    ModePickerRow(mode: mode, availability: availability)
                }
                .disabled(!availability.isAvailable || !mode.isImplemented)
            }
            .navigationTitle("Tarama modu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            }
        }
    }
}
