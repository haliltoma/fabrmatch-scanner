import SwiftUI
import ScanLabCore

/// Top status bar: time, triangles, thermal, guidance (PRD §8 screen 2).
struct ScanHUD: View {
    let elapsed: TimeInterval
    let triangles: Int
    let thermal: ThermalLevel
    let warning: CaptureWarning?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Label(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)), systemImage: "timer")
                Label(triangles.formatted(.number.notation(.compactName)), systemImage: "triangle")
                    .accessibilityLabel("\(triangles) üçgen")
                Label(thermal.title, systemImage: "thermometer.medium")
                    .foregroundStyle(thermal >= .serious ? .orange : .primary)
            }
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .capsule)

            if let warning {
                Label(warning.message, systemImage: warning.systemImage)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.85), in: .capsule)
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: warning)
    }
}

extension ThermalLevel {
    var title: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Ilık"
        case .serious: "Sıcak"
        case .critical: "Kritik"
        }
    }
}
