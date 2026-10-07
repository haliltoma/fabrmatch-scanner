import SwiftUI
import ScanLabCore

/// Routes a scan request to the screen of its capture mode.
struct ScanContainer: View {
    let request: ScanRequest
    let onClose: (UUID?) -> Void

    var body: some View {
        modeView
            // Keep the screen awake for the whole capture, including processing and saving.
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var modeView: some View {
        switch request.mode {
        case .lidarMesh, .pointCloud:
            ScanView(request: request, onClose: onClose)
        case .trueDepth:
            TrueDepthScanView(request: request, onClose: onClose)
        case .roomPlan:
            RoomPlanScanView(request: request, onClose: onClose)
        case .objectCapture:
            ObjectCaptureScanView(request: request, onClose: onClose)
        case .photoVideo:
            PhotoCaptureView(request: request, onClose: onClose)
        }
    }
}
