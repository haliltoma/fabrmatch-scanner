import Foundation
import Testing
@testable import ScanLabCore
@testable import ScanLabExport

@Suite struct ExporterTests {
    static let optionMatrix: [ExportOptions] = [
        ExportOptions(),
        ExportOptions(unit: .millimeters, upAxis: .z),
        ExportOptions(unit: .centimeters, upAxis: .y),
        ExportOptions(unit: .inches, upAxis: .z),
    ]

    @Test("Round-trip keeps triangle count and bounds (FR-13.5)", arguments: ExportFormat.allCases, optionMatrix)
    func roundTrip(format: ExportFormat, options: ExportOptions) throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("cube.\(format.fileExtension)")
        let mesh = ExportFixtures.cube
        try format.exporter.export(mesh, to: url, options: options)
        let result = try ExportVerifier.verify(mesh, exportedTo: url, format: format, options: options)
        #expect(result.passed, "\(result)")
    }

    @Test("Binary STL size is 84 + 50·n bytes")
    func stlSize() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("c.stl")
        try STLBinaryExporter().export(ExportFixtures.cube, to: url, options: ExportOptions())
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        #expect(size == 84 + 50 * 12)
    }

    @Test func stlNormalsPointOutward() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("c.stl")
        try STLBinaryExporter().export(ExportFixtures.cube, to: url, options: ExportOptions())
        var r = ByteReader(try Data(contentsOf: url), offset: 84)
        let firstNormal = try r.readVector()   // bottom face (z = 0) → -Z
        #expect(firstNormal == SIMD3(0, 0, -1))
    }

    @Test func plyPreservesColorsAndWelding() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("c.ply")
        let mesh = ExportFixtures.cube
        try PLYBinaryExporter().export(mesh, to: url, options: ExportOptions())
        let back = try PLYBinaryReader().read(from: url, options: ExportOptions())
        #expect(back.vertexCount == 8)
        #expect(back.colors == mesh.colors)
        #expect(back.indices == mesh.indices)
    }

    @Test func millimeterExportScalesCoordinates() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("c.obj")
        try OBJExporter().export(ExportFixtures.cube, to: url, options: ExportOptions(unit: .millimeters))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("v 300.0 300.0 300.0"))
    }

    @Test func objReaderFansPolygons() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("quad.obj")
        try "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1/1/1 2/2/2 3/3/3 4/4/4\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try OBJReader().read(from: url, options: ExportOptions()).triangleCount == 2)
    }

    @Test("Empty mesh exports and verifies", arguments: ExportFormat.allCases)
    func emptyMesh(format: ExportFormat) throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("e.\(format.fileExtension)")
        try format.exporter.export(TriangleMesh(), to: url, options: ExportOptions())
        #expect(try ExportVerifier.verify(TriangleMesh(), exportedTo: url, format: format, options: ExportOptions()).passed)
    }

    @Test("Z-up conversion is invertible", arguments: [SIMD3<Float>(1, 2, 3), SIMD3(-0.5, 0, 7)])
    func axisInverse(p: SIMD3<Float>) {
        let o = ExportOptions(unit: .millimeters, upAxis: .z)
        let back = o.inverseTransform(o.transform(p))
        #expect(abs(back.x - p.x) < 1e-5 && abs(back.y - p.y) < 1e-5 && abs(back.z - p.z) < 1e-5)
        #expect(o.transform(SIMD3(0, 1, 0)) == SIMD3(0, 0, 1000))
    }

    @Test("A point-cloud PLY without any face element reads as points")
    func plyWithoutFaceElement() throws {
        let tmp = try TemporaryDirectory()
        let url = tmp.url.appendingPathComponent("cloud.ply")
        var w = ByteWriter()
        w.write(bytes: Array("ply\nformat binary_little_endian 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nend_header\n".utf8))
        w.write(SIMD3<Float>(1, 2, 3)); w.write(SIMD3<Float>(4, 5, 6))
        try w.data.write(to: url)
        let m = try PLYBinaryReader().read(from: url, options: ExportOptions())
        #expect(m.vertexCount == 2 && m.triangleCount == 0 && m.positions[1] == SIMD3(4, 5, 6))
    }
}
