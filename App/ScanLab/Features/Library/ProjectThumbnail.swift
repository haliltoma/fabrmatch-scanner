import SwiftUI

/// Loads the cached `thumbnail.jpg` off the main actor; placeholder when missing.
struct ProjectThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cube.transparent")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: url) { image = await Self.load(url) }
    }

    @concurrent
    private static func load(_ url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 168, height: 168))
    }
}
