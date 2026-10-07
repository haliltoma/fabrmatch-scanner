import Foundation
import simd

/// A two-point distance measurement (FR-11.1, FR-11.8), world coordinates in meters.
nonisolated struct Measurement: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var note: String = ""
    var createdAt = Date.now

    var meters: Float { simd_distance(a, b) }
}

/// `measurements.json` per scan output: a dictionary keyed by the viewed source.
nonisolated enum MeasurementFile {
    static func load(_ url: URL, key: String) -> [Measurement] {
        guard let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [Measurement]].self, from: data) else { return [] }
        return all[key] ?? []
    }

    static func save(_ items: [Measurement], to url: URL, key: String) throws {
        var all = (try? JSONDecoder().decode([String: [Measurement]].self, from: Data(contentsOf: url))) ?? [:]
        all[key] = items
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(all).write(to: url, options: .atomic)
    }
}
