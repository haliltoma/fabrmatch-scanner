// Mac photogrammetry for Object Capture / photo scans taken on the iPhone.
// The phone can only build `.reduced` models; the Mac rebuilds the same images at full/raw detail.
//
//   swift scanlab-mac/tools/photogrammetry.swift <images-dir> <out.usdz> [preview|reduced|medium|full|raw] [--normal]
//
// Defaults: full detail, high feature sensitivity (helps smooth / low-texture parts), object masking on.
import Foundation
import RealityKit

let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let flags = Set(CommandLine.arguments.filter { $0.hasPrefix("--") })
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: photogrammetry.swift <images-dir> <out.usdz> [detail] [--normal]\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[args.startIndex])
let output = URL(fileURLWithPath: args[args.startIndex + 1])
let detailName = args.count > 2 ? args[args.startIndex + 2] : "full"
let detail: PhotogrammetrySession.Request.Detail = switch detailName {
case "preview": .preview
case "reduced": .reduced
case "medium": .medium
case "raw": .raw
default: .full
}

var config = PhotogrammetrySession.Configuration()
config.featureSensitivity = flags.contains("--normal") ? .normal : .high
config.sampleOrdering = .sequential
config.isObjectMaskingEnabled = true

let session = try PhotogrammetrySession(input: input, configuration: config)
try session.process(requests: [.modelFile(url: output, detail: detail)])
var last = -1
for try await out in session.outputs {
    switch out {
    case .requestProgress(_, let f):
        let pct = Int(f * 100)
        if pct / 10 != last / 10 { print("progress \(pct)%"); last = pct }
    case .requestError(_, let error):
        print("error: \(error)"); exit(1)
    case .invalidSample(let id, let reason):
        print("invalid sample \(id): \(reason)")
    case .skippedSample(let id):
        print("skipped sample \(id)")
    case .processingComplete:
        print("done → \(output.path)"); exit(0)
    default: break
    }
}
