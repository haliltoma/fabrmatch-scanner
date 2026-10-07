import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        #if DEBUG
        // Development hook: SCANLAB_VIEW=<file or mesh_chunks dir> opens the viewer directly
        // (used to check rendering in the simulator, where taps cannot be scripted).
        if let path = ProcessInfo.processInfo.environment["SCANLAB_VIEW"] {
            let url = URL(filePath: path)
            ViewerView(request: ViewerRequest(title: url.lastPathComponent,
                                              source: url.lastPathComponent == "mesh_chunks" ? .meshChunks(url) : .file(url),
                                              measurementsURL: nil, thumbnailURL: nil))
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder
    private var main: some View {
        if hasCompletedOnboarding {
            LibraryView()
        } else {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}
