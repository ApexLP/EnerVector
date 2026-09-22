import UIKit

/// Draws as-built floor plans and roof outlines with Core Graphics.
/// The same drawing code backs the in-app views and the PDF report, so what you see is what you export.
enum PlanRenderer {
    struct Style {
        var wall = UIColor(white: 0.15, alpha: 1)
        var dimension = UIColor(red: 0.12, green: 0.43, blue: 0.92, alpha: 1)
        var objectFill = UIColor(red: 0.12, green: 0.43, blue: 0.92, alpha: 0.12)
        var objectStroke = UIColor(red: 0.12, green: 0.43, blue: 0.92, alpha: 0.9)
        var background = UIColor.white
        static let light = Style()
    }

    // MARK: Floor plan

    static func image(_ g: RoomGeometry, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            draw(g, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }

    static func draw(_ g: RoomGeometry, in ctx: CGContext, rect: CGRect, style: Style = .light, showDimensions: Bool = true) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        style.background.setFill()
        ctx.fill(rect)

        let pts = g.allPoints
        guard !pts.isEmpty else {
            drawCentered("No geometry", in: rect, font: .systemFont(ofSize: 12), color: .gray)
            return
        }
        let map = Mapper(points: pts, rect: rect, padding: showDimensions ? 34 : 12)

        // Objects (equipment footprints)
        for obj in g.objects {
            let path = UIBezierPath()
            for (i, c) in obj.corners.enumerated() {
                i == 0 ? path.move(to: map(c)) : path.addLine(to: map(c))
            }
            path.close()
            style.objectFill.setFill()
            path.fill()
            style.objectStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
            let center = map(obj.center)
            drawCentered(obj.label, in: CGRect(x: center.x - 50, y: center.y - 7, width: 100, height: 14),
                         font: .systemFont(ofSize: 8, weight: .semibold), color: style.objectStroke)
        }

        // Walls
        ctx.setLineCap(.square)
        ctx.setLineWidth(max(3, map.scale * 0.15))
        ctx.setStrokeColor(style.wall.cgColor)
        for w in g.walls {
            ctx.move(to: map(w.a))
            ctx.addLine(to: map(w.b))
        }
        ctx.strokePath()

        // Openings — knock out the wall, then mark the type.
        for o in g.openings {
            ctx.setLineWidth(max(4, map.scale * 0.15) + 1)
            ctx.setStrokeColor(style.background.cgColor)
            ctx.move(to: map(o.a)); ctx.addLine(to: map(o.b)); ctx.strokePath()
            switch o.kind {
            case .door:
                let a = map(o.a), b = map(o.b)
                let r = hypot(b.x - a.x, b.y - a.y)
                let angle = atan2(b.y - a.y, b.x - a.x)
                ctx.setLineWidth(0.8)
                ctx.setStrokeColor(style.wall.withAlphaComponent(0.6).cgColor)
                ctx.move(to: a)
                ctx.addLine(to: CGPoint(x: a.x + r * cos(angle - .pi / 2), y: a.y + r * sin(angle - .pi / 2)))
                ctx.addArc(center: a, radius: r, startAngle: angle - .pi / 2, endAngle: angle, clockwise: false)
                ctx.strokePath()
            case .window:
                ctx.setLineWidth(2)
                ctx.setStrokeColor(UIColor.systemTeal.cgColor)
                ctx.move(to: map(o.a)); ctx.addLine(to: map(o.b)); ctx.strokePath()
            case .opening, .wall:
                break
            }
        }

        if showDimensions {
            let centroid = map(PlanPoint(x: pts.map(\.x).reduce(0, +) / Double(pts.count), y: pts.map(\.y).reduce(0, +) / Double(pts.count)))
            for w in g.walls where w.length > 0.6 {
                drawDimension(Units.feetInches(w.length), a: map(w.a), b: map(w.b), awayFrom: centroid, in: ctx, color: style.dimension)
            }
        }
        drawScaleBar(map: map, in: ctx, rect: rect, color: style.wall)
    }

    // MARK: Roof plan

    static func roofImage(_ plan: RoofPlan, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            drawRoof(plan, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }

    static func drawRoof(_ plan: RoofPlan, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        UIColor(white: 0.96, alpha: 1).setFill()
        ctx.fill(rect)
        let pts = plan.outline + plan.obstructions.flatMap(\.points)
        guard plan.outline.count > 2 else {
            drawCentered("No roof outline traced", in: rect, font: .systemFont(ofSize: 12), color: .gray)
            return
        }
        let map = Mapper(points: pts, rect: rect, padding: 24)

        func path(_ p: [PlanPoint]) -> UIBezierPath {
            let bp = UIBezierPath()
            for (i, pt) in p.enumerated() { i == 0 ? bp.move(to: map(pt)) : bp.addLine(to: map(pt)) }
            bp.close()
            return bp
        }

        let outline = path(plan.outline)
        UIColor.systemGreen.withAlphaComponent(0.18).setFill()
        outline.fill()
        UIColor.systemGreen.setStroke()
        outline.lineWidth = 2
        outline.stroke()

        for obs in plan.obstructions where obs.points.count > 2 {
            let p = path(obs.points)
            UIColor.systemRed.withAlphaComponent(0.25).setFill()
            p.fill()
            UIColor.systemRed.setStroke()
            p.lineWidth = 1.2
            p.stroke()
            let b = p.bounds
            drawCentered(obs.label, in: CGRect(x: b.midX - 40, y: b.midY - 6, width: 80, height: 12),
                         font: .systemFont(ofSize: 8, weight: .semibold), color: .systemRed)
        }
        drawScaleBar(map: map, in: ctx, rect: rect, color: .darkGray)
    }

    // MARK: Helpers

    private struct Mapper {
        let minX: Double, minY: Double, scale: CGFloat, origin: CGPoint

        init(points: [PlanPoint], rect: CGRect, padding: CGFloat) {
            let xs = points.map(\.x), ys = points.map(\.y)
            minX = xs.min() ?? 0
            minY = ys.min() ?? 0
            let w = max((xs.max() ?? 1) - minX, 0.01), h = max((ys.max() ?? 1) - minY, 0.01)
            let avail = rect.insetBy(dx: padding, dy: padding)
            scale = min(avail.width / w, avail.height / h)
            origin = CGPoint(x: avail.minX + (avail.width - CGFloat(w) * scale) / 2,
                             y: avail.minY + (avail.height - CGFloat(h) * scale) / 2)
        }

        func callAsFunction(_ p: PlanPoint) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(p.x - minX) * scale, y: origin.y + CGFloat(p.y - minY) * scale)
        }
    }

    private static func drawDimension(_ text: String, a: CGPoint, b: CGPoint, awayFrom c: CGPoint, in ctx: CGContext, color: UIColor) {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var angle = atan2(b.y - a.y, b.x - a.x)
        var normal = CGPoint(x: -sin(angle), y: cos(angle))
        if (mid.x - c.x) * normal.x + (mid.y - c.y) * normal.y < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }

        let offset: CGFloat = 12
        ctx.saveGState()
        ctx.translateBy(x: mid.x + normal.x * offset, y: mid.y + normal.y * offset)
        ctx.rotate(by: angle)
        drawCentered(text, in: CGRect(x: -45, y: -6, width: 90, height: 12), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium), color: color)
        ctx.restoreGState()
    }

    private static func drawScaleBar(map: Mapper, in ctx: CGContext, rect: CGRect, color: UIColor) {
        // Pick a round length in feet that is ~20% of the drawing width.
        let targetFt = Double(rect.width * 0.2 / map.scale) * Units.feetPerMeter
        let options: [Double] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 500]
        let ft = options.last { $0 <= targetFt } ?? 1
        let px = CGFloat(ft / Units.feetPerMeter) * map.scale
        let y = rect.maxY - 10, x = rect.minX + 10
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + px, y: y))
        ctx.move(to: CGPoint(x: x, y: y - 3)); ctx.addLine(to: CGPoint(x: x, y: y + 3))
        ctx.move(to: CGPoint(x: x + px, y: y - 3)); ctx.addLine(to: CGPoint(x: x + px, y: y + 3))
        ctx.strokePath()
        let label = "\(Int(ft)) ft" as NSString
        label.draw(at: CGPoint(x: x + px + 4, y: y - 6), withAttributes: [.font: UIFont.systemFont(ofSize: 7.5), .foregroundColor: color])
    }

    static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
}
