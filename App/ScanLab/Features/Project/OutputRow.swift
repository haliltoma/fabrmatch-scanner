import SwiftUI

struct OutputRow: View {
    let file: URL
    let onView: () -> Void
    let onExport: () -> Void

    private var viewable: Bool { ["usdz", "ply", "stl", "obj", "pdf"].contains(file.pathExtension.lowercased()) }
    private var convertible: Bool { file.pathExtension.lowercased() != "pdf" }

    var body: some View {
        HStack {
            Label(file.lastPathComponent, systemImage: viewable ? "cube.transparent" : "doc.text")
                .font(.subheadline)
            Spacer()
            if viewable {
                Button("Görüntüle", action: onView).buttonStyle(.borderless)
                if convertible {
                    Button("Dönüştür", systemImage: "arrow.triangle.2.circlepath", action: onExport)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Paylaş")
        }
    }
}
