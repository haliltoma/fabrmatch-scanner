import SceneKit
import SwiftUI

/// SCNView with orbit/pan/zoom camera control (FR-10.1) and tap-to-pick for measurements (FR-11.1).
struct SceneViewContainer: UIViewRepresentable {
    let model: ViewerModel
    let onSceneReady: (SCNScene, SCNView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = SCNScene()
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        guard let content = model.content, let scene = view.scene else { return }
        if c.shownMode != model.mode || !c.hasContent {
            c.contentNode?.removeFromParentNode()
            let node = SceneBuilder.node(for: content, mode: model.mode)
            scene.rootNode.addChildNode(node)
            c.contentNode = node
            if !c.hasContent {
                c.hasContent = true
                fit(view, node: node)
                onSceneReady(scene, view)
            }
            c.shownMode = model.mode
        }
        if c.fitToken != model.fitToken, let node = c.contentNode {
            c.fitToken = model.fitToken
            fit(view, node: node)
        }
        c.drawMeasurements(in: scene)
    }

    /// Frames the content: camera on a diagonal, far enough to see the bounding sphere.
    private func fit(_ view: SCNView, node: SCNNode) {
        let (center, radius) = node.boundingSphere
        let r = max(Float(radius), 0.01)
        let camera = SCNCamera()
        camera.zNear = Double(r) * 0.01
        camera.zFar = Double(r) * 100
        // The app is portrait-only, so the horizontal axis is the narrow one. (view.bounds is still
        // zero on the first update, so it cannot be used to decide.)
        let fov: Float = 45
        camera.projectionDirection = .horizontal
        camera.fieldOfView = CGFloat(fov)
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let dir = simd_normalize(SIMD3<Float>(1, 0.8, 1.2))
        let distance = r / sin(fov / 2 * .pi / 180) * 1.25
        let pos = SIMD3<Float>(Float(center.x), Float(center.y), Float(center.z)) + dir * distance
        cameraNode.simdPosition = pos
        cameraNode.simdLook(at: SIMD3(Float(center.x), Float(center.y), Float(center.z)))
        view.scene?.rootNode.childNodes.filter { $0.camera != nil }.forEach { $0.removeFromParentNode() }
        view.scene?.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        view.defaultCameraController.target = center
    }

    final class Coordinator: NSObject {
        let model: ViewerModel
        weak var view: SCNView?
        var contentNode: SCNNode?
        var shownMode: DisplayMode?
        var hasContent = false
        var fitToken = 0
        private let overlay = SCNNode()

        init(model: ViewerModel) {
            self.model = model
        }

        @MainActor @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard model.measuring, let view else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue,
                                                                          .ignoreHiddenNodes: true])
            guard let hit = hits.first(where: { !isOverlay($0.node) }) else { return }
            let w = hit.worldCoordinates
            model.tapped(world: SIMD3(Float(w.x), Float(w.y), Float(w.z)))
        }

        /// Measurement markers must not be picked as surface points.
        private func isOverlay(_ node: SCNNode) -> Bool {
            var n: SCNNode? = node
            while let current = n {
                if current === overlay { return true }
                n = current.parent
            }
            return false
        }

        @MainActor func drawMeasurements(in scene: SCNScene) {
            if overlay.parent == nil { scene.rootNode.addChildNode(overlay) }
            overlay.childNodes.forEach { $0.removeFromParentNode() }
            let r = max(Float(contentNode?.boundingSphere.radius ?? 0.1), 0.01)
            let dot = r * 0.012
            func marker(_ p: SIMD3<Float>, _ color: UIColor) {
                let s = SCNSphere(radius: CGFloat(dot))
                s.firstMaterial?.diffuse.contents = color
                s.firstMaterial?.lightingModel = .constant
                s.firstMaterial?.readsFromDepthBuffer = false
                let n = SCNNode(geometry: s)
                n.simdPosition = p
                n.renderingOrder = 100
                overlay.addChildNode(n)
            }
            for m in model.measurements {
                marker(m.a, .systemYellow)
                marker(m.b, .systemYellow)
                let line = SCNGeometry(sources: [SCNGeometrySource(vertices: [SCNVector3(m.a.x, m.a.y, m.a.z), SCNVector3(m.b.x, m.b.y, m.b.z)])],
                                       elements: [SCNGeometryElement(indices: [UInt16(0), 1], primitiveType: .line)])
                line.firstMaterial?.diffuse.contents = UIColor.systemYellow
                line.firstMaterial?.lightingModel = .constant
                line.firstMaterial?.readsFromDepthBuffer = false
                let n = SCNNode(geometry: line)
                n.renderingOrder = 100
                overlay.addChildNode(n)
            }
            if let p = model.pendingPoint { marker(p, .systemRed) }
        }
    }
}
