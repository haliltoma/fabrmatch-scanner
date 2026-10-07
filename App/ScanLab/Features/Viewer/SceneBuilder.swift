import ScanLabCore
import SceneKit
import UIKit

/// Turns `ViewerContent` into SceneKit nodes for a display mode.
enum SceneBuilder {
    /// ARMeshClassification raw values → colours (FR-3.2).
    static let classColors: [UInt8: UIColor] = [
        0: .systemGray, 1: .systemBlue, 2: .systemGreen, 3: .systemTeal,
        4: .systemOrange, 5: .systemPurple, 6: .systemCyan, 7: .systemBrown,
    ]

    static func node(for content: ViewerContent, mode: DisplayMode) -> SCNNode {
        switch content {
        case .mesh(let mesh):
            return mode == .points ? pointsNode(mesh.positions) : meshNode(mesh, mode: mode)
        case .points(let points):
            return pointsNode(points)
        case .scene(let scene):
            let root = SCNNode()
            for child in scene.rootNode.childNodes { root.addChildNode(child.clone()) }
            if mode == .wireframe {
                root.enumerateHierarchy { node, _ in node.geometry?.materials.forEach { $0.fillMode = .lines } }
            }
            return root
        }
    }

    /// Flat shading: every triangle gets its own vertices and face normal. Averaged vertex normals
    /// smear sharp edges into blotches, which reads badly on engineering parts.
    static func meshNode(_ mesh: TriangleMesh, mode: DisplayMode) -> SCNNode {
        let n = mesh.triangleCount
        var positions = [SCNVector3](), normals = [SCNVector3]()
        positions.reserveCapacity(3 * n)
        normals.reserveCapacity(3 * n)
        let classify = mode == .classification && mesh.faceClassifications.count == n
        var colors = [SIMD4<Float>]()
        if classify { colors.reserveCapacity(3 * n) }
        for t in 0..<n {
            let (a, b, c) = mesh.triangle(t)
            let fn = mesh.faceNormal(t)
            let normal = SCNVector3(fn.x, fn.y, fn.z)
            for p in [a, b, c] {
                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(normal)
            }
            if classify {
                let col = (classColors[mesh.faceClassifications[t]] ?? .systemGray).rgba
                colors += [col, col, col]
            }
        }
        var sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)]
        if classify {
            let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                             componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }
        let element = SCNGeometryElement(indices: (0..<UInt32(3 * n)).map { $0 }, primitiveType: .triangles)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.7
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        material.diffuse.contents = classify ? UIColor.white : UIColor(white: 0.8, alpha: 1)
        if mode == .wireframe { material.fillMode = .lines }
        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    static func pointsNode(_ points: [SIMD3<Float>]) -> SCNNode {
        let source = SCNGeometrySource(vertices: points.map { SCNVector3($0.x, $0.y, $0.z) })
        let element = SCNGeometryElement(indices: (0..<UInt32(points.count)).map { $0 }, primitiveType: .point)
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 4
        // Colour by height so the shape reads without lighting (FR-4.8).
        let ys = points.map(\.y)
        let lo = ys.min() ?? 0, hi = max((ys.max() ?? 1), lo + 1e-6)
        let colors = points.map { p -> SIMD4<Float> in
            let t = (p.y - lo) / (hi - lo)
            return SIMD4(0.2 + 0.8 * t, 0.45 + 0.3 * (1 - abs(2 * t - 1)), 1 - 0.8 * t, 1)
        }
        let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: data, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let geometry = SCNGeometry(sources: [source, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}

extension UIColor {
    var rgba: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
