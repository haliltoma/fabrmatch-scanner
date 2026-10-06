import SwiftUI
import ScanLabCore

struct ProjectRow: View {
    let summary: ProjectSummary

    var body: some View {
        HStack(spacing: 12) {
            ProjectThumbnail(url: summary.paths.thumbnail)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.project.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(summary.project.createdAt, format: .dateTime.day().month().year())
                    Text(summary.sizeBytes, format: .byteCount(style: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !summary.project.tags.isEmpty {
                    Text(summary.project.tags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            ForEach(summary.project.modes.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { mode in
                Image(systemName: mode.systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(mode.title)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
