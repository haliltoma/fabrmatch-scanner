import SwiftUI
import ScanLabCore

/// M18 subset needed for F1: quality, range, raw data, units, plus device capabilities.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.quality) private var quality = QualityProfile.balanced
    @AppStorage(SettingsKeys.maxRange) private var maxRange = 5.0
    @AppStorage(SettingsKeys.keepRawData) private var keepRawData = true
    @AppStorage(SettingsKeys.units) private var units = LengthUnit.meters

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarama") {
                    Picker("Kalite profili", selection: $quality) {
                        ForEach(QualityProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Maksimum menzil: \(maxRange, format: .number.precision(.fractionLength(1))) m")
                        Slider(value: $maxRange, in: 1...5, step: 0.5)
                            .accessibilityLabel("Maksimum menzil")
                    }
                    Toggle("Ham veriyi tut", isOn: $keepRawData)
                }
                Section("Birimler") {
                    Picker("Uzunluk", selection: $units) {
                        ForEach(LengthUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                    }
                }
                Section("Cihaz") {
                    ForEach(Capability.allCases, id: \.self) { capability in
                        LabeledContent(capability.displayName) {
                            Image(systemName: appModel.capabilities.contains(capability) ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(appModel.capabilities.contains(capability) ? .green : .secondary)
                                .accessibilityLabel(appModel.capabilities.contains(capability) ? "Destekleniyor" : "Desteklenmiyor")
                        }
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
        }
    }
}

extension QualityProfile {
    var title: String {
        switch self {
        case .fast: "Hızlı"
        case .balanced: "Dengeli"
        case .high: "Yüksek"
        }
    }
}
