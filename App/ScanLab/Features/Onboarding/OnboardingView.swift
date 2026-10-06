import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $selection) {
                ForEach(OnboardingPage.all) { page in
                    OnboardingPageView(page: page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(isLastPage ? "Başla" : "İleri", action: advance)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom)
        }
    }

    private var isLastPage: Bool { selection == OnboardingPage.all.count - 1 }

    private func advance() {
        if isLastPage {
            onFinish()
        } else {
            withAnimation { selection += 1 }
        }
    }
}
