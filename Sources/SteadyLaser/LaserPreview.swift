import AppKit
import QuartzCore
import SwiftUI

/// The pointer as it's set now, on a sample slide in the settings window.
/// It's drawn by the same renderer as the real one, and to scale: the slide
/// stands for one filling the main screen, shrunk to the preview's width.
/// With the mouse over it, it follows the mouse through the same filter.
struct LaserPreview: NSViewRepresentable {
    /// Everything about the pointer the preview shows.
    struct Look: Equatable {
        var kind: PointerKind
        var style: LaserStyle
        var radius: CGFloat
        var spotlightRadius: CGFloat
        var spotlightShade: CGFloat
        var color: LaserColor
        var stability: Stability
        var hideCursor: Bool

        @MainActor init(_ s: Settings) {
            kind = s.kind
            style = s.style
            radius = s.size.radius
            spotlightRadius = s.spotlightSize.radius
            spotlightShade = s.spotlightShade.alpha
            color = s.color
            stability = s.stability
            hideCursor = s.hideCursor
        }
    }

    var look: Look

    func makeNSView(context: Context) -> LaserPreviewView { LaserPreviewView(look: look) }

    func updateNSView(_ view: LaserPreviewView, context: Context) { view.look = look }
}

@MainActor
final class LaserPreviewView: NSView {
    var look: LaserPreview.Look {
        didSet { if look != oldValue { applyLook() } }
    }

    private let slide = SampleSlide.makeLayer(title: "Quarterly results", contentsScale: 2)
    private let renderer = LaserRenderer()
    private var link: CADisplayLink?
    private var filter = OneEuroFilter2D(minCutoff: 1.8, beta: 0.006)
    private var trail: [TrailPoint] = []
    private var following = false
    private let trailDuration = Settings.shared.trailDuration

    init(look: LaserPreview.Look) {
        self.look = look
        super.init(frame: .zero)
        let root = CALayer()
        layer = root          // layer-hosting view: we own the layer tree
        wantsLayer = true
        slide.anchorPoint = .zero
        root.addSublayer(slide)
        root.addSublayer(renderer.container)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("ตัวอย่างตัวชี้บนสไลด์")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Preview points per screen point: the slide stands for the main screen.
    private var scale: CGFloat {
        bounds.width / (NSScreen.main?.frame.width ?? 1512)
    }

    /// Where the pointer rests while the mouse is elsewhere, in view coordinates.
    private var restPoint: CGPoint {
        let s = bounds.width / SampleSlide.size.width
        return CGPoint(x: SampleSlide.aboveTallestBar.x * s, y: bounds.height - SampleSlide.aboveTallestBar.y * s)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let s = bounds.width / SampleSlide.size.width
        slide.position = CGPoint(x: 0, y: bounds.height - SampleSlide.size.height * s)
        slide.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        CATransaction.commit()
        applyLook()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyLook()
    }

    private func applyLook() {
        guard bounds.width > 0 else { return }
        renderer.configure(
            kind: look.kind,
            style: look.style,
            radius: look.radius * scale,
            spotlightRadius: look.spotlightRadius * scale,
            spotlightShade: look.spotlightShade,
            color: look.color.color,
            scale: window?.backingScaleFactor ?? 2,
            canvas: bounds.size
        )
        filter.minCutoff = look.stability.minCutoff
        filter.beta = look.stability.beta
        window?.invalidateCursorRects(for: self)
        if !following { rest() }
    }

    private func rest() {
        trail.removeAll()
        filter.reset()
        renderer.update(point: restPoint, opacity: 1, trail: [], now: CACurrentMediaTime(), trailDuration: trailDuration)
    }

    // MARK: Following the mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        following = true
        filter.reset()
        trail.removeAll()
        if link == nil {
            let l = displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    override func mouseExited(with event: NSEvent) {
        stopFollowing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopFollowing() }
    }

    private func stopFollowing() {
        following = false
        link?.invalidate()
        link = nil
        rest()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let window else { return stopFollowing() }
        let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(mouse) else { return stopFollowing() }
        let now = CACurrentMediaTime()
        let point = filter.filter(mouse, time: now)
        if let last = trail.last, hypot(point.x - last.point.x, point.y - last.point.y) < 0.05 {
            // Not moving: don't grow the tail with duplicate points.
        } else {
            trail.append(TrailPoint(point: point, time: now))
        }
        trail.removeAll { now - $0.time > trailDuration }
        renderer.update(point: point, opacity: 1, trail: trail, now: now, trailDuration: trailDuration)
    }

    // The pointer stands in for the cursor here, as it does on screen.
    override func resetCursorRects() {
        if look.hideCursor { addCursorRect(bounds, cursor: Self.noCursor) }
    }

    private static let noCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
}
