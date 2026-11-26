import AppKit
import QuartzCore

struct TrailPoint {
    var point: CGPoint
    var time: CFTimeInterval
}

/// The laser itself, built from Core Animation layers so the GPU composites
/// it. Nothing is redrawn on the CPU per frame; we only move layers, with
/// implicit animations off so the dot lands exactly where we put it.
///
///   glow  — wide, faint radial halo (Glow / Comet)
///   tail  — one tapered ribbon along the recent path, fading toward the end (Comet)
///   spot  — the dot: white-hot center, saturated body, soft edge
@MainActor
final class LaserRenderer {
    let container = CALayer()

    private let glow = CAGradientLayer()
    private let tail = CAGradientLayer()
    private let tailShape = CAShapeLayer()
    private let spot = CAGradientLayer()

    private var style: LaserStyle = .comet
    private var radius: CGFloat = 9

    init() {
        container.isHidden = true
        container.anchorPoint = .zero
        container.frame = .zero

        tail.type = .axial
        tail.mask = tailShape
        tailShape.fillColor = NSColor.white.cgColor

        for g in [glow, spot] {
            g.type = .radial
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
        }

        container.addSublayer(glow)
        container.addSublayer(tail)
        container.addSublayer(spot)
    }

    func configure(style: LaserStyle, radius r: CGFloat, color: NSColor, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        self.style = style
        self.radius = r
        let c = color.usingColorSpace(.sRGB) ?? color

        for layer in [container, glow, tail, tailShape, spot] {
            layer.contentsScale = scale
        }

        glow.isHidden = (style == .dot)
        let glowDiameter = r * 2 * 3.4
        glow.bounds = CGRect(x: 0, y: 0, width: glowDiameter, height: glowDiameter)
        glow.colors = [c.withAlphaComponent(0.50), c.withAlphaComponent(0.20), c.withAlphaComponent(0)].map(\.cgColor)
        glow.locations = [0, 0.3, 1]

        tail.isHidden = (style != .comet)
        tail.colors = [c.withAlphaComponent(0), c.withAlphaComponent(0.25), c.withAlphaComponent(0.7)].map(\.cgColor)
        tail.locations = [0, 0.45, 1]

        // The spot is a bit larger than the core radius so the edge can fade
        // out softly instead of ending in a hard ring.
        let spotDiameter = r * 2 * 1.2
        spot.bounds = CGRect(x: 0, y: 0, width: spotDiameter, height: spotDiameter)
        let hot = c.blended(withFraction: 0.55, of: .white) ?? c
        spot.colors = [
            NSColor.white,
            hot,
            c,
            c.withAlphaComponent(0.85),
            c.withAlphaComponent(0),
        ].map(\.cgColor)
        spot.locations = [0, 0.2, 0.6, 0.8, 1]
    }

    /// `point` and `trail` are in the overlay view's coordinates.
    func update(point: CGPoint, opacity: CGFloat, trail: [TrailPoint], now: CFTimeInterval, trailDuration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard opacity > 0.001 else {
            container.isHidden = true
            return
        }
        container.isHidden = false
        container.opacity = Float(opacity)

        glow.position = point
        spot.position = point

        guard style == .comet else { return }
        updateTail(head: point, trail: trail, now: now, duration: trailDuration)
    }

    /// Builds a ribbon whose half-width shrinks with each sample's age, then
    /// fills it with a gradient running from the oldest sample to the head.
    private func updateTail(head: CGPoint, trail: [TrailPoint], now: CFTimeInterval, duration: CFTimeInterval) {
        // Drop samples closer than half a point to their neighbour so the
        // direction (and the ribbon's normals) stay stable.
        var pts: [(p: CGPoint, w: CGFloat)] = []
        for s in trail {
            let freshness = CGFloat(max(0, 1 - (now - s.time) / duration))
            if let last = pts.last, hypot(s.point.x - last.p.x, s.point.y - last.p.y) < 0.5 { continue }
            pts.append((s.point, radius * 0.85 * freshness))
        }
        if let last = pts.last, hypot(head.x - last.p.x, head.y - last.p.y) >= 0.5 {
            pts.append((head, radius * 0.85))
        } else if !pts.isEmpty {
            pts[pts.count - 1] = (head, radius * 0.85)
        }

        guard pts.count >= 2,
              hypot(head.x - pts[0].p.x, head.y - pts[0].p.y) > radius * 0.5
        else {
            tail.isHidden = true
            return
        }
        tail.isHidden = false

        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in pts.indices {
            let a = pts[max(i - 1, 0)].p, b = pts[min(i + 1, pts.count - 1)].p
            var dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            dx /= len; dy /= len
            let w = pts[i].w
            left.append(CGPoint(x: pts[i].p.x - dy * w, y: pts[i].p.y + dx * w))
            right.append(CGPoint(x: pts[i].p.x + dy * w, y: pts[i].p.y - dx * w))
        }

        let all = left + right
        let minX = all.map(\.x).min()! - 1, maxX = all.map(\.x).max()! + 1
        let minY = all.map(\.y).min()! - 1, maxY = all.map(\.y).max()! + 1
        let box = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))

        let path = CGMutablePath()
        path.addLines(between: (left + right.reversed()).map { CGPoint(x: $0.x - box.minX, y: $0.y - box.minY) })
        path.closeSubpath()

        tail.frame = box
        tailShape.frame = tail.bounds
        tailShape.path = path

        let unit = { (p: CGPoint) in CGPoint(x: (p.x - box.minX) / box.width, y: (p.y - box.minY) / box.height) }
        tail.startPoint = unit(pts[0].p)
        tail.endPoint = unit(head)
    }
}
