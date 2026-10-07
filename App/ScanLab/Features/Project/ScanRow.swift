import SwiftUI
import ScanLabCore

struct ScanRow: View {
    let scan: ScanRecord
    var canExport = true
    let onExport: () -> Void

    var body: some View {
        HStack {
            Image(systemName: scan.mode.systemImage)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.mode.title).font(.headline)
                Text("\(scan.stats.triangles > 0 ? "\(scan.stats.triangles.formatted()) üçgen" : "\(scan.stats.vertices.formatted()) öğe") · \(Duration.seconds(scan.stats.durationSec).formatted(.time(pattern: .minuteSecond)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canExport {
                Button("Dışa aktar", systemImage: "square.and.arrow.up", action: onExport)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("scan.export")
            }
        }
    }
}
