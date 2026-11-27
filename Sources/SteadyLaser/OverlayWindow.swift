import AppKit
import QuartzCore

/// A transparent, click-through window covering one screen, above full-screen
/// apps (Keynote / PowerPoint slideshows) and on every Space.
@MainActor
final class OverlayWindow: NSWindow {
    let laserView: LaserView

    init(screen: NSScreen, controller: LaserController) {
        laserView = LaserView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: controller)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = laserView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the laser layers and drives rendering from a display link, so each
/// frame is drawn in step with this screen's refresh rate (60 / 120 Hz).
@MainActor
final class LaserView: NSView {
    private unowned let controller: LaserController
    private let renderer = LaserRenderer()
    private var link: CADisplayLink?

    init(frame: NSRect, controller: LaserController) {
        self.controller = controller
        super.init(frame: frame)
        let root = CALayer()
        layer = root          // layer-hosting view: we own the layer tree
        wantsLayer = true
        root.addSublayer(renderer.container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        applyStyle()
    }

    func applyStyle() {
        let s = Settings.shared
        renderer.configure(
            kind: s.kind,
            style: s.style,
            radius: s.size.radius,
            color: s.color.color,
            scale: window?.backingScaleFactor ?? 2,
            canvas: bounds.size
        )
    }

    func setPaused(_ paused: Bool) {
        link?.isPaused = paused
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        controller.update(now: now)
        render(now: now)
    }

    private func render(now: CFTimeInterval) {
        guard let window else { return }
        let origin = window.frame.origin
        let local = { (p: CGPoint) in CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

        let point = local(controller.position)
        // Draw only on the screen the laser is on (with some margin for the glow).
        let onThisScreen = bounds.insetBy(dx: -80, dy: -80).contains(point)
        let trail = controller.trail.map { TrailPoint(point: local($0.point), time: $0.time) }

        renderer.update(
            point: point,
            opacity: onThisScreen ? controller.opacity : 0,
            trail: trail,
            now: now,
            trailDuration: Settings.shared.trailDuration
        )
    }
}
