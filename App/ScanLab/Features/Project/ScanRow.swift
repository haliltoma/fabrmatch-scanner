import SwiftUI
import ScanLabCore

struct ScanRow: View {
    let scan: ScanRecord
    let onExport: () -> Void

    var body: some View {
        HStack {
            Image(systemName: scan.mode.systemImage)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.mode.title).font(.headline)
                Text("\(scan.stats.triangles.formatted()) üçgen · \(Duration.seconds(scan.stats.durationSec).formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dışa aktar", systemImage: "square.and.arrow.up", action: onExport)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}
