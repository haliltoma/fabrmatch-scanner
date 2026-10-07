import SwiftUI

@main
struct ScanLabApp: App {
    @State private var appModel = AppModel()

    init() {
        #if DEBUG
        // UI tests: start from a fresh onboarding without pinning the value in the argument domain
        // (an "-hasCompletedOnboarding NO" argument would override the app's own write forever).
        if UserDefaults.standard.bool(forKey: "ScanLabResetOnboarding") {
            // An explicit false overrides any lower-priority domain (removeObject left a stale true).
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task { await appModel.launch() }
        }
    }
}
