import simd

/// Decides which ARKit frames are worth recording for reconstruction (PRD §4.5 step 3, FR-8.1).
/// A frame is kept when tracking is good and the camera moved or turned enough since the last
/// keyframe, so the views cover the part without thousands of near-duplicates.
public struct KeyframePolicy: Sendable {
    public var minTranslation: Float
    public var minRotationDegrees: Float
    public var minInterval: Double

    public init(minTranslation: Float, minRotationDegrees: Float, minInterval: Double = 0.1) {
        self.minTranslation = minTranslation
        self.minRotationDegrees = minRotationDegrees
        self.minInterval = minInterval
    }

    public init(profile: QualityProfile) {
        self.init(minTranslation: profile.keyframeDistance, minRotationDegrees: profile.keyframeAngle)
    }

    private var last: (pose: simd_float4x4, time: Double)?

    /// Returns true and remembers the frame when it should be recorded.
    public mutating func accept(pose: simd_float4x4, time: Double, trackingIsNormal: Bool) -> Bool {
        guard trackingIsNormal else { return false }
        guard let last else {
            self.last = (pose, time)
            return true
        }
        guard time - last.time >= minInterval else { return false }
        let moved = simd_distance(SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z),
                                  SIMD3(last.pose.columns.3.x, last.pose.columns.3.y, last.pose.columns.3.z))
        // Angle between viewing directions (−Z axes).
        let a = -SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        let b = -SIMD3(last.pose.columns.2.x, last.pose.columns.2.y, last.pose.columns.2.z)
        let turned = acos(min(1, max(-1, simd_dot(simd_normalize(a), simd_normalize(b))))) * 180 / .pi
        guard moved >= minTranslation || turned >= minRotationDegrees else { return false }
        self.last = (pose, time)
        return true
    }
}
