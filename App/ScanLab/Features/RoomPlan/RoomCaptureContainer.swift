import RoomPlan
import SwiftUI

/// Hosts Apple's RoomCaptureView and forwards its result.
struct RoomCaptureContainer: UIViewRepresentable {
    let model: RoomPlanModel
    @Binding var stopToken: Int

    func makeCoordinator() -> RoomCaptureCoordinator { RoomCaptureCoordinator(model: model) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopToken != context.coordinator.handledStop {
            context.coordinator.handledStop = stopToken
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        view.captureSession.stop()
    }
}

/// Top-level (not nested): RoomCaptureViewDelegate inherits NSCoding, which needs a stable class name.
final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    let model: RoomPlanModel
    weak var view: RoomCaptureView?
    var handledStop = 0

    init(model: RoomPlanModel) {
        self.model = model
    }

    // RoomCaptureViewDelegate inherits NSCoding; the coordinator is never archived.
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        model.processed(processedResult, error: error)
    }
}
