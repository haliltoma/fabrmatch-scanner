import ARKit
import Foundation
import Observation
import ScanLabCore

@Observable
final class PhotoCaptureModel {
    enum Phase: Equatable { case preparing, ready, recording, paused, saving, finished, failed(String) }

    let request: ScanRequest
    let session = ARSession()
    private(set) var phase: Phase = .preparing
    private(set) var frames = 0
    private let store: ProjectStore
    private var slot: ScanSlot?
    private var recorder: PhotoRecorder?
    private var startedAt = Date.now

    init(request: ScanRequest, store: ProjectStore) {
        self.request = request
        self.store = store
    }

    func prepare() async {
        do {
            let slot = try await ScanSlot.open(request, sensor: .photo, store: store, quality: .high)
            let images = slot.paths.root.appendingPathComponent("splat/images", isDirectory: true)
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            let recorder = PhotoRecorder(imagesDirectory: images) { [weak self] n in
                Task { @MainActor in self?.frames = n }
            }
            session.delegate = recorder
            session.delegateQueue = recorder.queue
            let config = ARWorldTrackingConfiguration()
            if let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
                config.videoFormat = format
            }
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.slot = slot
            self.recorder = recorder
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func toggle() {
        switch phase {
        case .ready, .paused:
            recorder?.setRecording(true)
            phase = .recording
        case .recording:
            recorder?.setRecording(false)
            phase = .paused
        default: break
        }
    }

    func finish() async -> UUID? {
        guard let slot, let recorder else { return nil }
        recorder.setRecording(false)
        phase = .saving
        session.pause()
        do {
            guard let transforms = await Task.detached(priority: .userInitiated, operation: { recorder.finish() }).value,
                  !transforms.frames.isEmpty else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Hiç kare kaydedilmedi."])
            }
            try transforms.encoded().write(to: slot.paths.root.appendingPathComponent("splat/transforms.json"), options: .atomic)
            try await slot.close(stats: ScanStats(vertices: transforms.frames.count, triangles: 0,
                                                  durationSec: Date.now.timeIntervalSince(startedAt).rounded()))
            phase = .finished
            return slot.projectID
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    func discard() async {
        session.pause()
        await slot?.discard()
    }
}
