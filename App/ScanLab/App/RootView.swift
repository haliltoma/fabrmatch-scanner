import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            LibraryView()
        } else {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }
}
