import AppKit
import SwiftUI

extension DevTools {
    /// Renders the settings window offscreen, side by side: Laser in light
    /// mode and Spotlight in dark mode. Uses its own defaults, not the user's.
    static func snapshotSettings(to path: String) {
        let domain = "local.steadylaser.snapshot"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        guard let defaults = UserDefaults(suiteName: domain) else { return }
        let settings = Settings(defaults: defaults)

        let size = NSSize(width: 560, height: 1320)
        var images: [NSBitmapImageRep] = []
        for (kind, appearance) in [(PointerKind.laser, NSAppearance.Name.aqua), (.spotlight, .darkAqua)] {
            settings.kind = kind
            let view = NSHostingView(rootView: SettingsView(model: AppModel(settings: settings)))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // let SwiftUI and the layers draw
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            images.append(rep)
        }

        let gap = 24
        let w = images.map(\.pixelsWide).reduce(0, +) + gap * (images.count - 1)
        let h = images.map(\.pixelsHigh).max() ?? 0
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var x = 0
        for rep in images {
            if let cg = rep.cgImage {
                ctx.draw(cg, in: CGRect(x: x, y: h - rep.pixelsHigh, width: rep.pixelsWide, height: rep.pixelsHigh))
            }
            x += rep.pixelsWide + gap
        }
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
