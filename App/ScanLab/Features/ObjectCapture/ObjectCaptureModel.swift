import Foundation
import Observation
import RealityKit
import ScanLabCore
import SwiftUI

/// Object Capture (PRD M5): Apple's guided photo capture, then on-device photogrammetry → textured USDZ.
/// The photos stay in the scan folder (`images/`) so the Mac can reconstruct them again at Full/Raw detail.
@Observable
final class ObjectCaptureModel {
    enum Phase: Equatable { case preparing, capturing, passComplete, reconstructing(Double), finished, failed(String) }

    let request: ScanRequest
    private(set) var phase: Phase = .preparing
    private(set) var session: ObjectCaptureSession?
    private let store: ProjectStore
    private var slot: ScanSlot?
    private var startedAt = Date.now
    private var watcher: Task<Void, Never>?

    init(request: ScanRequest, store: ProjectStore) {
        self.request = request
        self.store = store
    }

    var images: URL? { slot?.paths.root.appendingPathComponent("images", isDirectory: true) }

    func prepare() async {
        guard ObjectCaptureSession.isSupported else {
            phase = .failed("Bu cihaz Object Capture'ı desteklemiyor.")
            return
        }
        do {
            let slot = try await ScanSlot.open(request, sensor: .photo, store: store, quality: .high)
            let images = slot.paths.root.appendingPathComponent("images", isDirectory: true)
            let checkpoint = slot.paths.root.appendingPathComponent("checkpoint", isDirectory: true)
            for dir in [images, checkpoint] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            var config = ObjectCaptureSession.Configuration()
            config.checkpointDirectory = checkpoint
            let session = ObjectCaptureSession()
            session.start(imagesDirectory: images, configuration: config)
            self.slot = slot
            self.session = session
            startedAt = .now
            phase = .capturing
            watch(session)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func watch(_ session: ObjectCaptureSession) {
        watcher = Task { [weak self] in
            for await state in session.stateUpdates {
                guard let self else { return }
                switch state {
                case .completed: await self.reconstruct()
                case .failed(let error): self.phase = .failed(error.localizedDescription)
                default: break
                }
            }
        }
        Task { [weak self] in
            for await done in session.userCompletedScanPassUpdates where done {
                self?.phase = .passComplete
            }
        }
    }

    /// The single primary action for the current capture state.
    var primaryAction: (title: String, run: () -> Void)? {
        guard let session else { return nil }
        switch session.state {
        case .ready: return ("Nesneyi algıla", { _ = session.startDetecting() })
        case .detecting: return ("Çekime başla", { session.startCapturing() })
        default: return nil
        }
    }

    func newPass(flipped: Bool) {
        guard let session else { return }
        flipped ? session.beginNewScanPassAfterFlip() : session.beginNewScanPass()
        phase = .capturing
    }

    func finishCapture() { session?.finish() }

    private func reconstruct() async {
        guard let slot, let images else { return }
        let output = slot.paths.root.appendingPathComponent("model.usdz")
        phase = .reconstructing(0)
        do {
            guard PhotogrammetrySession.isSupported else {
                throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey:
                    "Cihazda fotogrametri desteklenmiyor; fotoğraflar kaydedildi, Mac'te işlenebilir."])
            }
            let photogrammetry = try PhotogrammetrySession(input: images)
            try photogrammetry.process(requests: [.modelFile(url: output, detail: .reduced)])
            for try await out in photogrammetry.outputs {
                switch out {
                case .requestProgress(_, let fraction): phase = .reconstructing(fraction)
                case .requestError(_, let error): throw error
                case .processingComplete:
                    let shots = (try? FileManager.default.contentsOfDirectory(atPath: images.path).count) ?? 0
                    try await slot.close(stats: ScanStats(vertices: shots, triangles: 0,
                                                          durationSec: Date.now.timeIntervalSince(startedAt).rounded()))
                    phase = .finished
                    return
                default: break
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    var projectID: UUID? { slot?.projectID }

    func discard() async {
        watcher?.cancel()
        session?.cancel()
        await slot?.discard()
    }
}
