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
    /// Live capture guidance from the session (too close, too fast, too dark…).
    private(set) var feedback: Set<ObjectCaptureSession.Feedback> = []
    private(set) var shots = 0
    /// Orbits finished so far. Apple's guidance — and what the reconstruction needs to see every side —
    /// is three orbits at different heights, plus a flipped one for the underside.
    private(set) var completedPasses = 0
    static let recommendedPasses = 3
    /// Below this the solver lacks overlap and the shape comes out lumpy (the 25-photo bottle did).
    static let minimumShots = 60
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
            // Extra frames for the Mac's full-detail rebuild of the same capture.
            config.isOverCaptureEnabled = true
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
                guard let self else { return }
                self.completedPasses += 1
                self.phase = .passComplete
            }
        }
        Task { [weak self] in
            for await feedback in session.feedbackUpdates { self?.feedback = feedback }
        }
        Task { [weak self] in
            for await shots in session.numberOfShotsTakenUpdates { self?.shots = shots }
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

    /// Why finishing now would give a poor model, or nil when the capture is complete enough.
    var finishWarning: String? {
        if shots < Self.minimumShots {
            return "\(shots) fotoğraf çekildi; düzgün bir model için en az \(Self.minimumShots) gerekir. Az fotoğrafla yüzeyler buruşuk ve eğik çıkar."
        }
        if completedPasses < Self.recommendedPasses {
            return "\(completedPasses)/\(Self.recommendedPasses) tur tamamlandı. Üst ve alt kenarlar eksik kalabilir."
        }
        return nil
    }

    private func reconstruct() async {
        guard let slot, let images else { return }
        let output = slot.paths.root.appendingPathComponent("model.usdz")
        phase = .reconstructing(0)
        do {
            guard PhotogrammetrySession.isSupported else {
                throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey:
                    "Cihazda fotogrametri desteklenmiyor; fotoğraflar kaydedildi, Mac'te işlenebilir."])
            }
            // High sensitivity finds features on smooth, low-texture parts; the photos are taken in
            // orbit order, so sequential matching is both faster and more robust.
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high
            config.sampleOrdering = .sequential
            config.isObjectMaskingEnabled = true
            let photogrammetry = try PhotogrammetrySession(input: images, configuration: config)
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
