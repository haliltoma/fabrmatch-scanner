import ScanLabCore

extension ScanModeID {
    var title: String {
        CaptureModeDescriptor.all.first { $0.id == self }?.title ?? rawValue
    }

    var systemImage: String {
        CaptureModeDescriptor.all.first { $0.id == self }?.systemImage ?? "cube"
    }
}
