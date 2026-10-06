// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanLabKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ScanLabCore", targets: ["ScanLabCore"]),
        .library(name: "ScanLabExport", targets: ["ScanLabExport"]),
        .library(name: "ScanLabSensor", targets: ["ScanLabSensor"]),
    ],
    targets: [
        .target(name: "ScanLabCore"),
        .target(name: "ScanLabExport", dependencies: ["ScanLabCore"]),
        .target(name: "ScanLabSensor", dependencies: ["ScanLabCore"]),
        .testTarget(name: "ScanLabCoreTests", dependencies: ["ScanLabCore"]),
        .testTarget(name: "ScanLabExportTests", dependencies: ["ScanLabCore", "ScanLabExport"]),
        .testTarget(name: "ScanLabSensorTests", dependencies: ["ScanLabCore", "ScanLabSensor"]),
    ],
    swiftLanguageModes: [.v6]
)
