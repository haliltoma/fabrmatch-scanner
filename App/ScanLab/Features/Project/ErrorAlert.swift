import SwiftUI

/// Shows `ProjectDetailModel.errorMessage` as an alert, binding straight to the observable model.
struct ErrorAlert: ViewModifier {
    @Bindable var model: ProjectDetailModel

    func body(content: Content) -> some View {
        content.alert("Hata", isPresented: Binding(isPresent: $model.errorMessage)) {
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
