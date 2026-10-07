import SwiftUI

struct OnboardingPageView: View {
    let page: OnboardingPage
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 72.0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: page.systemImage)
                .font(.system(size: symbolSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
