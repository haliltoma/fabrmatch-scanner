import SwiftUI

struct RenameProjectView: View {
    let onSave: (String) -> Void
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(initialName: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Proje adı", text: $name)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle("Yeniden adlandır")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        onSave(name)
        dismiss()
    }
}
