import AppKit
import QuartzCore

/// Developer helpers, run from the command line instead of the menu bar app:
///   SteadyLaser --snapshot out.png   render every style/color to a PNG
///   SteadyLaser --selftest           print One Euro filter jitter / lag numbers
@MainActor
enum DevTools {
    static func snapshot(to path: String) {
        let cell = CGSize(width: 220, height: 170)
        let styles = LaserStyle.allCases   // the spotlight is too big for a cell: --snapshot-spotlight
        let backgrounds: [NSColor] = [NSColor(white: 0.96, alpha: 1), NSColor(white: 0.12, alpha: 1)]
        let colors: [LaserColor] = [.red, .green]
        let size = CGSize(width: cell.width * CGFloat(styles.count), height: cell.height * CGFloat(backgrounds.count * colors.count))
        let scale: CGFloat = 2
        let now: CFTimeInterval = 100

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor.black.cgColor

        var row = 0
        for bg in backgrounds {
            for color in colors {
                for (col, style) in styles.enumerated() {
                    let frame = CGRect(x: CGFloat(col) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height)
                    let back = CALayer()
                    back.frame = frame
                    back.backgroundColor = bg.cgColor
                    root.addSublayer(back)

                    let r = LaserRenderer()
                    r.configure(kind: .laser, style: style, radius: LaserSize.medium.radius, color: color.color, scale: scale, canvas: cell)
                    back.addSublayer(r.container)

                    // A fake recent path curving in from the lower left.
                    let end = CGPoint(x: cell.width * 0.62, y: cell.height * 0.55)
                    var trail: [TrailPoint] = []
                    for i in 0...14 {
                        let f = CGFloat(i) / 14
                        let p = CGPoint(x: end.x - 95 * (1 - f), y: end.y - 40 * (1 - f) * (1 - f))
                        trail.append(TrailPoint(point: p, time: now - 0.12 * Double(1 - f)))
                    }
                    r.update(point: end, opacity: 1, trail: trail, now: now, trailDuration: 0.12)
                }
                row += 1
            }
        }

        guard let ctx = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.scaleBy(x: scale, y: scale)
        root.render(in: ctx)
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    /// Renders the spotlight at each size over a mock slide, one panel per size.
    static func snapshotSpotlight(to path: String) {
        let slide = CGSize(width: 640, height: 360)
        let scale: CGFloat = 2
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: slide.width, height: slide.height * CGFloat(SpotlightSize.allCases.count))
        root.isGeometryFlipped = true

        for (i, size) in SpotlightSize.allCases.enumerated() {
            let back = CALayer()
            back.frame = CGRect(x: 0, y: CGFloat(i) * slide.height, width: slide.width, height: slide.height)
            back.backgroundColor = NSColor.white.cgColor
            back.masksToBounds = true
            root.addSublayer(back)

            // A fake slide: title, a few bullet bars and a chart.
            let title = CATextLayer()
            title.string = "Quarterly results (\(size.rawValue))"
            title.fontSize = 30
            title.foregroundColor = NSColor(white: 0.1, alpha: 1).cgColor
            title.contentsScale = scale
            title.frame = CGRect(x: 40, y: 28, width: 560, height: 40)
            back.addSublayer(title)
            for row in 0..<4 {
                let bar = CALayer()
                bar.backgroundColor = NSColor(white: 0.55, alpha: 1).cgColor
                bar.frame = CGRect(x: 40, y: 100 + CGFloat(row) * 44, width: [260, 220, 280, 180][row], height: 14)
                back.addSublayer(bar)
            }
            for col in 0..<4 {
                let h = [90, 140, 120, 190][col]
                let bar = CALayer()
                bar.backgroundColor = [NSColor.systemBlue, .systemGreen, .systemOrange, .systemRed][col].cgColor
                bar.frame = CGRect(x: 380 + CGFloat(col) * 56, y: 300 - CGFloat(h), width: 40, height: CGFloat(h))
                back.addSublayer(bar)
            }

            let r = LaserRenderer()
            r.configure(kind: .spotlight, style: .comet, radius: LaserSize.medium.radius, spotlightRadius: size.radius,
                        color: LaserColor.red.color, scale: scale, canvas: slide)
            back.addSublayer(r.container)
            r.update(point: CGPoint(x: 460, y: 200), opacity: 1, trail: [], now: 0, trailDuration: 0.12)
        }

        guard let ctx = CGContext(
            data: nil, width: Int(root.bounds.width * scale), height: Int(root.bounds.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        // The layer tree is top-down (flipped); flip the bitmap to match.
        ctx.translateBy(x: 0, y: CGFloat(ctx.height))
        ctx.scaleBy(x: scale, y: -scale)
        root.render(in: ctx)
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    /// Renders the "set laser button" panel content offscreen, with the hint visible.
    static func snapshotCapturePanel(to path: String) {
        let capture = ButtonCapture()
        let view = capture.makeContent()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = "ตั้งปุ่มเลเซอร์"
        window.appearance = NSAppearance(named: .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) size \(view.bounds.size)")
    }

    /// Simulates a hand-held air mouse at 120 Hz: holding still with ±3 px
    /// tremor, then sweeping at 1500 px/s. Prints how much jitter survives the
    /// filter and how far the dot trails behind during the sweep.
    static func selfTest() {
        var rng = SystemRandomNumberGenerator()
        let dt = 1.0 / 120.0
        for stability in Stability.allCases {
            var f = OneEuroFilter2D(minCutoff: stability.minCutoff, beta: stability.beta)
            var t = 0.0

            // 2 s holding still around (500, 500) with integer-pixel tremor.
            var inSpread = 0.0, outSpread = 0.0
            var prevIn = CGPoint(x: 500, y: 500), prevOut = prevIn
            for i in 0..<240 {
                let p = CGPoint(x: 500 + Double(Int.random(in: -3...3, using: &rng)),
                                y: 500 + Double(Int.random(in: -3...3, using: &rng)))
                let o = f.filter(p, time: t)
                if i > 30 {
                    inSpread += hypot(p.x - prevIn.x, p.y - prevIn.y)
                    outSpread += hypot(o.x - prevOut.x, o.y - prevOut.y)
                }
                prevIn = p; prevOut = o; t += dt
            }

            // 0.5 s sweep at 1500 px/s.
            var lag = 0.0
            var x = 500.0
            for _ in 0..<60 {
                x += 1500 * dt
                let o = f.filter(CGPoint(x: x, y: 500), time: t)
                lag = x - o.x
                t += dt
            }
            print(String(format: "%-7@ jitter per frame: raw %.2f px -> laser %.2f px (%.0f%% less) | lag at 1500 px/s: %.1f px (%.1f ms)",
                         stability.rawValue as NSString, inSpread / 209, outSpread / 209,
                         100 * (1 - outSpread / inSpread), lag, lag / 1500 * 1000))
        }
    }
}
