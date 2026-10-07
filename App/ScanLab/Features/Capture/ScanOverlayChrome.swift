import SwiftUI

/// Shared top status capsule and bottom control row for the custom capture screens.
struct StatusCapsule: View {
    let lines: [String]
    let warning: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(lines.joined(separator: "  ·  "))
                .font(.subheadline.monospacedDigit())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
            if let warning {
                Text(warning)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.85), in: .capsule)
                    .foregroundStyle(.white)
            }
        }
        .animation(.default, value: warning)
    }
}

struct CaptureFailureView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Tarama başlatılamadı", systemImage: "exclamationmark.triangle", description: Text(message))
            Button("Kapat", action: onClose).buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding()
    }
}
