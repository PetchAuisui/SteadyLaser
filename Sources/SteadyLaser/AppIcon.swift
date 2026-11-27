import AppKit
import QuartzCore

extension DevTools {
    /// Draws the app icon as a 1024 × 1024 PNG: a dark rounded square with a
    /// slide on it, and the app's own comet laser pointing at the chart.
    ///
    ///     SteadyLaser --render-icon AppIcon.png
    ///
    /// `build.sh --icon` turns the PNG into Resources/AppIcon.icns.
    static func renderIcon(to path: String) {
        let side: CGFloat = 1024
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: side, height: side)

        // Apple's icon grid: an 824 pt body with a 100 pt margin and a
        // continuous corner of about 185 pt. Coordinates are y-up.
        let body = CAGradientLayer()
        body.frame = CGRect(x: 100, y: 100, width: 824, height: 824)
        body.cornerRadius = 185
        body.cornerCurve = .continuous
        body.masksToBounds = true
        body.colors = [
            NSColor(srgbRed: 0.15, green: 0.18, blue: 0.27, alpha: 1),
            NSColor(srgbRed: 0.04, green: 0.05, blue: 0.09, alpha: 1),
        ].map(\.cgColor)
        body.startPoint = CGPoint(x: 0.5, y: 1)
        body.endPoint = CGPoint(x: 0.5, y: 0)
        body.borderWidth = 3
        body.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        root.addSublayer(body)

        // The slide.
        let slide = CALayer()
        slide.frame = CGRect(x: 112, y: 196, width: 600, height: 400)
        slide.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        slide.cornerRadius = 30
        slide.cornerCurve = .continuous
        body.addSublayer(slide)

        func bar(_ rect: CGRect, _ color: NSColor, radius: CGFloat) {
            let l = CALayer()
            l.frame = rect
            l.backgroundColor = color.cgColor
            l.cornerRadius = radius
            slide.addSublayer(l)
        }
        // Title and bullet lines.
        bar(CGRect(x: 48, y: 318, width: 300, height: 34), NSColor(white: 0.22, alpha: 1), radius: 17)
        for (i, w) in [190.0, 210, 160].enumerated() {
            bar(CGRect(x: 48, y: 244 - Double(i) * 52, width: w, height: 20), NSColor(white: 0.70, alpha: 1), radius: 10)
        }
        // Chart: the last, tallest bar is what the laser points at.
        let chart: [(h: CGFloat, color: NSColor)] = [
            (110, NSColor(srgbRed: 0.20, green: 0.52, blue: 0.98, alpha: 1)),
            (165, NSColor(srgbRed: 0.20, green: 0.78, blue: 0.40, alpha: 1)),
            (135, NSColor(srgbRed: 1.00, green: 0.62, blue: 0.10, alpha: 1)),
            (245, NSColor(srgbRed: 0.98, green: 0.30, blue: 0.30, alpha: 1)),
        ]
        for (i, b) in chart.enumerated() {
            bar(CGRect(x: 330 + CGFloat(i) * 62, y: 56, width: 42, height: b.h), b.color, radius: 8)
        }

        // The laser, drawn by the app's own renderer, sweeping up from the
        // lower left onto the top of the tallest bar.
        let renderer = LaserRenderer()
        renderer.configure(kind: .laser, style: .comet, radius: 34, color: LaserColor.red.color,
                           scale: 1, canvas: body.bounds.size)
        body.addSublayer(renderer.container)
        let tip = CGPoint(x: 112 + 330 + 3 * 62 + 21, y: 196 + 56 + 245 + 22)
        let now: CFTimeInterval = 100
        var trail: [TrailPoint] = []
        for i in 0...16 {
            let f = CGFloat(i) / 16
            let p = CGPoint(x: tip.x - 260 * (1 - f), y: tip.y - 150 * (1 - f) * (1 - f))
            trail.append(TrailPoint(point: p, time: now - 0.12 * Double(1 - f)))
        }
        renderer.update(point: tip, opacity: 1, trail: trail, now: now, trailDuration: 0.12)

        guard let ctx = CGContext(
            data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        root.render(in: ctx)
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
