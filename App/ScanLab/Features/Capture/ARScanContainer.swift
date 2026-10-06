import ARKit
import RealityKit
import SwiftUI

/// Live camera + mesh overlay. F1 uses RealityKit's scene-understanding wireframe;
/// the custom Metal renderer with classification colors arrives in F2 (M10).
struct ARScanContainer: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.debugOptions.insert(.showSceneUnderstanding)
        view.renderOptions.insert(.disableMotionBlur)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
