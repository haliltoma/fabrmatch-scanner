import Foundation

/// What to open in the 3D viewer (PRD M10).
struct ViewerRequest: Identifiable, Hashable {
    enum Source: Hashable {
        /// LiDAR anchor chunks (`raw/mesh_chunks`), merged on load.
        case meshChunks(URL)
        /// A file the app wrote: PLY (mesh or point cloud, mm), USDZ, OBJ, STL.
        case file(URL)
    }

    let id = UUID()
    let title: String
    let source: Source
    /// Where measurements of this scan are kept, and where a missing project thumbnail is written.
    let measurementsURL: URL?
    let thumbnailURL: URL?
    /// Where edits (crops) are saved as new files; nil disables saving.
    var outputDirectory: URL? = nil
}
