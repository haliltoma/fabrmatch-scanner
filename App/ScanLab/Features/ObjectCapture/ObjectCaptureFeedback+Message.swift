import RealityKit
import SwiftUI  // ObjectCaptureSession lives in the RealityKit+SwiftUI cross-import overlay

extension ObjectCaptureSession.Feedback {
    var message: String {
        switch self {
        case .objectTooClose: "Çok yakın — biraz uzaklaş"
        case .objectTooFar: "Çok uzak — yaklaş"
        case .movingTooFast: "Yavaşla"
        case .environmentLowLight: "Işık az — ortamı aydınlat"
        case .environmentTooDark: "Çok karanlık"
        case .outOfFieldOfView: "Nesneyi kadrajda tut"
        case .objectNotFlippable: "Bu nesne ters çevrilmeye uygun görünmüyor"
        case .overCapturing: "Bu açı yeterli — sonraki bölgeye geç"
        case .objectNotDetected: "Nesne algılanamadı"
        @unknown default: "Kamerayı sabit tut"
        }
    }
}
