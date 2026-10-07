import Foundation
import RoomPlan
import UIKit

/// 2D floor plan PDF from a RoomPlan result (FR-6.4, FR-6.5): top view, wall lengths, doors and
/// windows, furniture outlines, scale bar and floor area — the deliverable Polycam/magicplan users expect.
enum FloorPlanRenderer {
    private struct Segment { let a: CGPoint; let b: CGPoint; var length: Float }

    static func render(_ room: CapturedRoom, title: String, to url: URL) throws {
        let walls = room.walls.map(segment)
        let openings = (room.doors.map { ($0, UIColor.systemBrown) } + room.windows.map { ($0, UIColor.systemCyan) }
                        + room.openings.map { ($0, UIColor.systemGray) }).map { (segment($0.0), $0.1) }
        let objects = room.objects.map(footprint)
        let allPoints = walls.flatMap { [$0.a, $0.b] } + objects.flatMap { $0 }
        guard let minX = allPoints.map(\.x).min(), let maxX = allPoints.map(\.x).max(),
              let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max() else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Odada duvar bulunamadı."])
        }

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)  // A4 landscape, points
        let drawing = page.insetBy(dx: 50, dy: 70)
        let scale = min(drawing.width / max(maxX - minX, 0.1), drawing.height / max(maxY - minY, 0.1))
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: drawing.minX + (p.x - minX) * scale + (drawing.width - (maxX - minX) * scale) / 2,
                    y: drawing.minY + (p.y - minY) * scale + (drawing.height - (maxY - minY) * scale) / 2)
        }
        let area = room.floors.reduce(Float(0)) { $0 + $1.dimensions.x * $1.dimensions.z }

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            let g = ctx.cgContext
            text(title, at: CGPoint(x: 50, y: 24), font: .boldSystemFont(ofSize: 16))
            text("\(Date.now.formatted(date: .abbreviated, time: .shortened)) · zemin ≈ \(area.formatted(.number.precision(.fractionLength(2)))) m² · "
                 + "\(room.walls.count) duvar, \(room.doors.count) kapı, \(room.windows.count) pencere",
                 at: CGPoint(x: 50, y: 44), font: .systemFont(ofSize: 10), color: .darkGray)

            // Furniture outlines.
            g.setStrokeColor(UIColor.systemGray3.cgColor)
            g.setLineWidth(1)
            for corners in objects {
                g.addLines(between: corners.map(map) + [map(corners[0])])
                g.strokePath()
            }
            // Walls.
            g.setStrokeColor(UIColor.black.cgColor)
            g.setLineWidth(4)
            g.setLineCap(.square)
            for w in walls {
                g.move(to: map(w.a)); g.addLine(to: map(w.b)); g.strokePath()
            }
            // Doors / windows / openings on top of the walls.
            g.setLineWidth(6)
            for (s, color) in openings {
                g.setStrokeColor(color.cgColor)
                g.move(to: map(s.a)); g.addLine(to: map(s.b)); g.strokePath()
            }
            // Wall length labels, offset to the outside of the wall's midpoint.
            let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            for w in walls {
                let mid = CGPoint(x: (w.a.x + w.b.x) / 2, y: (w.a.y + w.b.y) / 2)
                var n = CGVector(dx: -(w.b.y - w.a.y), dy: w.b.x - w.a.x)
                let len = max(hypot(n.dx, n.dy), 1e-6)
                n = CGVector(dx: n.dx / len, dy: n.dy / len)
                if (mid.x - center.x) * n.dx + (mid.y - center.y) * n.dy < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
                let p = map(mid)
                text(meters(w.length), at: CGPoint(x: p.x + n.dx * 14 - 18, y: p.y + n.dy * 14 - 6), font: .monospacedDigitSystemFont(ofSize: 9, weight: .medium))
            }
            // Scale bar: 1 m.
            let bar = CGRect(x: 50, y: page.height - 40, width: scale, height: 4)
            g.setFillColor(UIColor.black.cgColor)
            g.fill(bar)
            text("1 m", at: CGPoint(x: bar.maxX + 6, y: bar.minY - 5), font: .systemFont(ofSize: 9))
            text("ScanLab · RoomPlan", at: CGPoint(x: page.width - 140, y: page.height - 44), font: .systemFont(ofSize: 9), color: .gray)
        }
    }

    /// Creates `floorplan.pdf` from a saved `room.json` (scans made before this feature existed).
    static func renderSaved(roomJSON: URL, title: String, to url: URL) throws {
        let room = try JSONDecoder().decode(CapturedRoom.self, from: Data(contentsOf: roomJSON))
        try render(room, title: title, to: url)
    }

    private static func segment(_ s: CapturedRoom.Surface) -> Segment {
        let t = s.transform
        let center = CGPoint(x: CGFloat(t.columns.3.x), y: CGFloat(t.columns.3.z))
        var dir = CGVector(dx: CGFloat(t.columns.0.x), dy: CGFloat(t.columns.0.z))
        let l = max(hypot(dir.dx, dir.dy), 1e-6)
        dir = CGVector(dx: dir.dx / l, dy: dir.dy / l)
        let half = CGFloat(s.dimensions.x) / 2
        return Segment(a: CGPoint(x: center.x - dir.dx * half, y: center.y - dir.dy * half),
                       b: CGPoint(x: center.x + dir.dx * half, y: center.y + dir.dy * half), length: s.dimensions.x)
    }

    private static func footprint(_ o: CapturedRoom.Object) -> [CGPoint] {
        let t = o.transform
        let c = CGPoint(x: CGFloat(t.columns.3.x), y: CGFloat(t.columns.3.z))
        let ax = CGVector(dx: CGFloat(t.columns.0.x) * CGFloat(o.dimensions.x) / 2, dy: CGFloat(t.columns.0.z) * CGFloat(o.dimensions.x) / 2)
        let az = CGVector(dx: CGFloat(t.columns.2.x) * CGFloat(o.dimensions.z) / 2, dy: CGFloat(t.columns.2.z) * CGFloat(o.dimensions.z) / 2)
        return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { (sx, sz) in
            CGPoint(x: c.x + ax.dx * sx + az.dx * sz, y: c.y + ax.dy * sx + az.dy * sz)
        }
    }

    private static func meters(_ v: Float) -> String { "\(v.formatted(.number.precision(.fractionLength(2)))) m" }

    private static func text(_ s: String, at p: CGPoint, font: UIFont, color: UIColor = .black) {
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }
}
