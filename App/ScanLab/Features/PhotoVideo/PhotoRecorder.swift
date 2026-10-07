import ARKit
import CoreImage
import ScanLabCore

/// Records posed keyframes for Gaussian-splat / NeRF training (PRD M7): JPEG + pose per keyframe.
///
/// Safety invariant for `@unchecked Sendable`: state is touched only on `queue` (ARKit's delegateQueue);
/// JPEG encoding happens on `io` with copied pixel buffers, so the ARFrame is never retained.
nonisolated final class PhotoRecorder: NSObject, ARSessionDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "scanlab.photo", qos: .userInitiated)
    private let io = DispatchQueue(label: "scanlab.photo.io", qos: .utility)
    private let imagesDirectory: URL
    private let context = CIContext()
    private let onCount: @Sendable (Int) -> Void
    private var keyframes = KeyframePolicy(minTranslation: 0.08, minRotationDegrees: 8)
    private var transforms: NerfstudioTransforms?
    private var recording = false

    init(imagesDirectory: URL, onCount: @escaping @Sendable (Int) -> Void) {
        self.imagesDirectory = imagesDirectory
        self.onCount = onCount
    }

    func setRecording(_ on: Bool) { queue.async { self.recording = on } }

    /// Waits for pending JPEG writes and returns the transforms collected so far.
    func finish() -> NerfstudioTransforms? {
        io.sync {}
        return queue.sync { transforms }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard recording else { return }
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        guard keyframes.accept(pose: frame.camera.transform, time: frame.timestamp, trackingIsNormal: normal) else { return }
        let size = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        if transforms == nil {
            transforms = NerfstudioTransforms(flX: k[0][0], flY: k[1][1], cx: k[2][0], cy: k[2][1],
                                              w: Int(size.width), h: Int(size.height))
        }
        let index = (transforms?.frames.count ?? 0) + 1
        let name = "images/\(index.formatted(.number.precision(.integerLength(6)).grouping(.never))).jpg"
        transforms?.append(filePath: name, pose: frame.camera.transform)
        onCount(index)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)  // CIImage copies on render; buffer not retained after
        let url = imagesDirectory.deletingLastPathComponent().appendingPathComponent(name)
        let context = context
        io.async {
            try? context.writeJPEGRepresentation(of: image, to: url, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
        }
    }
}
