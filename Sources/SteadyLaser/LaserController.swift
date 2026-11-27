import AppKit
import QuartzCore

/// Owns the laser state shared by all screens: where the dot is (smoothed),
/// how visible it is, and the comet tail. Each screen's overlay view calls
/// `update(now:)` from its display link; with several screens the first call
/// in a frame does the work and the rest reuse it.
@MainActor
final class LaserController {
    private(set) var position: CGPoint = NSEvent.mouseLocation
    private(set) var opacity: CGFloat = 0
    private(set) var trail: [TrailPoint] = []

    private var windows: [OverlayWindow] = []
    private var filter = OneEuroFilter2D(minCutoff: 1.8, beta: 0.006)
    private var lastRaw: CGPoint?
    private var lastMoveTime: CFTimeInterval = -.infinity
    private var lastUpdate: CFTimeInterval = 0
    private var isPaused = false
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var wakeTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    func start() {
        rebuildWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }

        // Mouse moves wake the display links, and move the laser while the
        // real cursor is parked.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] e in
            MainActor.assumeIsolated { self?.mouseMoved(e) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] e in
            MainActor.assumeIsolated { self?.mouseMoved(e) }
            return e
        }

        // Fallback in case global mouse events don't arrive: cheap 30 Hz check
        // of the cursor position while everything else is paused.
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // While parked the real cursor stays put by design; moves arrive as events.
                guard let self, self.isPaused, self.parkedAt == nil, let last = self.lastRaw else { return }
                let p = NSEvent.mouseLocation
                if abs(p.x - last.x) > 0.5 || abs(p.y - last.y) > 0.5 { self.wakeIfNeeded() }
            }
        }
    }

    func stop() {
        CursorHider.setHidden(false)
        windows.forEach { $0.laserView.stop(); $0.close() }
        windows.removeAll()
    }

    /// Settings changed: restyle layers and make sure we're running.
    func settingsChanged() {
        windows.forEach { $0.laserView.applyStyle() }
        if !Settings.shared.detachCursor { parkedAt = nil }
        if Settings.shared.mode != .off || opacity > 0 { wake() }
    }

    private func rebuildWindows() {
        windows.forEach { $0.laserView.stop(); $0.close() }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0, controller: self) }
        windows.forEach { $0.orderFrontRegardless() }
        isPaused = false
    }

    /// Time source for the button's tap / hold / double-press timing (tests replace it).
    var clock: () -> CFTimeInterval = CACurrentMediaTime

    /// Set while the laser button is showing the laser.
    private(set) var buttonHeld = false
    private var buttonDownAt: CFTimeInterval = 0
    private var pressHidLaser = false

    /// A press shorter than this latches the laser on until the next press;
    /// a longer one is "hold to show". Remotes send short taps however long a
    /// key is held (the Norwii pointer sends ⌃L when a hold starts and ⌃A when
    /// it ends), so their taps always latch, and the next one turns it off.
    private let tapLength: CFTimeInterval = 0.3

    func laserButtonPressed() {
        if buttonHeld {
            // Latched on by an earlier tap: this press turns it off.
            pressHidLaser = true
            setButtonHeld(false)
        } else {
            pressHidLaser = false
            buttonDownAt = clock()
            setButtonHeld(true)
        }
    }

    func laserButtonReleased() {
        if pressHidLaser {
            pressHidLaser = false
            return
        }
        if clock() - buttonDownAt >= tapLength { setButtonHeld(false) }
    }

    /// The button was unbound or changed: drop any latched state.
    func resetLaserButton() {
        pressHidLaser = false
        setButtonHeld(false)
        lastHiddenAt = -.infinity
    }

    // MARK: Double press

    /// Called when the button is pressed twice in a row (switches Laser / Spotlight).
    var onDoublePress: (() -> Void)?

    private var shownAt: CFTimeInterval = -.infinity
    private var lastHiddenAt: CFTimeInterval = -.infinity
    private var lastShownFor: CFTimeInterval = .infinity
    private var secondOfDouble = false

    /// A double press is a short press, then another one after a pause of
    /// about half a second to a second and a half. It must be slow: the
    /// Norwii remote keeps a fast double click of Pointer for itself, to
    /// switch its own mode, and in its other mode Pointer sends nothing at
    /// all (no laser until it's double clicked back). The gap is measured
    /// from ⌃A to the laser showing, which is 0.1 s after ⌃L.
    /// Measured on 10 slow double presses: the remote sends ⌃A 0.7–1.0 s
    /// after a short press is let go, so a first press shows for 0.7–1.6 s;
    /// gaps were 0.7–1.4 s.
    private let doublePressFirstMax: CFTimeInterval = 1.8
    private let doublePressGapMin: CFTimeInterval = 0.6
    private let doublePressGapMax: CFTimeInterval = 1.6

    private func setButtonHeld(_ held: Bool) {
        guard held != buttonHeld else { return }
        buttonHeld = held
        DebugLog.write("button: laser \(held ? "on" : "off")")
        let now = clock()
        if held {
            // Start fresh at the cursor, no tail sweeping in from the old spot.
            filter.reset()
            trail.removeAll()
            let gap = now - lastHiddenAt
            secondOfDouble = lastShownFor < doublePressFirstMax && gap >= doublePressGapMin && gap < doublePressGapMax
            if secondOfDouble { onDoublePress?() }
            shownAt = now
            parkCursor()
        } else {
            unparkCursor()
            lastHiddenAt = now
            // The press that completed a double press can't start another,
            // so a quick third press starts over instead of switching back.
            lastShownFor = secondOfDouble ? .infinity : now - shownAt
        }
        wake()
    }

    // MARK: Virtual pointer
    //
    // While the laser button shows the laser, the real cursor stays where it
    // was and only the laser moves (by the mouse's moves), so the hidden
    // cursor doesn't hover over the Dock, buttons or links underneath.

    /// Where the laser is drawn while the cursor is parked (AppKit global
    /// coordinates). Kept through the fade-out, then dropped.
    private(set) var virtualPointer: CGPoint?
    /// Where the real cursor is parked; set while the button shows the laser.
    private(set) var parkedAt: CGPoint?
    /// Where the last press left the laser, and the cursor's spot then.
    private var resumeSpot: (laser: CGPoint, cursor: CGPoint)?

    /// The real cursor position (tests replace it).
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
    /// Puts the real cursor at `p`, AppKit global coordinates (tests replace it).
    var warpCursor: (CGPoint) -> Void = { p in
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: primaryTop - p.y))
        // Without this, real mouse moves are held back for a moment after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func parkCursor() {
        guard Settings.shared.detachCursor else { return }
        let here = mouseLocation()
        var start = here
        // The cursor hasn't moved since the last press: carry on from where
        // the laser was left, not from the parked cursor.
        if let r = resumeSpot, hypot(here.x - r.cursor.x, here.y - r.cursor.y) < 1 { start = r.laser }
        parkedAt = here
        virtualPointer = start
    }

    private func unparkCursor() {
        if let park = parkedAt, let laser = virtualPointer { resumeSpot = (laser, park) }
        parkedAt = nil
    }

    /// A mouse move while parked: move the laser by it and put the cursor back.
    /// `dy` is the event's deltaY, positive downward.
    func pointerMoved(dx: CGFloat, dy: CGFloat) {
        guard let park = parkedAt, let p = virtualPointer else { return }
        virtualPointer = clampToScreens(CGPoint(x: p.x + dx, y: p.y - dy))
        warpCursor(park)
    }

    private func mouseMoved(_ e: NSEvent) {
        if parkedAt != nil {
            DebugLog.write("move: dx \(e.deltaX) dy \(e.deltaY) at \(Int(e.locationInWindow.x)),\(Int(e.locationInWindow.y))")
            pointerMoved(dx: e.deltaX, dy: e.deltaY)
        }
        wakeIfNeeded()
    }

    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        let frames = NSScreen.screens.map(\.frame)
        guard let first = frames.first, !frames.contains(where: { $0.contains(p) }) else { return p }
        let all = frames.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: min(max(p.x, all.minX), all.maxX - 1), y: min(max(p.y, all.minY), all.maxY - 1))
    }

    private func wakeIfNeeded() {
        guard isPaused else { return }
        switch Settings.shared.mode {
        case .off, .hold:
            // Mouse movement alone doesn't show anything in these modes.
            guard opacity > 0 || buttonHeld else { return }
        case .moving, .always:
            break
        }
        wake()
    }

    private func wake() {
        isPaused = false
        windows.forEach { $0.laserView.setPaused(false) }
    }

    private func pauseAll() {
        isPaused = true
        windows.forEach { $0.laserView.setPaused(true) }
    }

    func update(now: CFTimeInterval) {
        // Already updated in this frame by another screen's display link.
        if now - lastUpdate < 0.002 { return }
        let dt = min(now - lastUpdate, 0.1)
        lastUpdate = now

        let s = Settings.shared
        filter.minCutoff = s.stability.minCutoff
        filter.beta = s.stability.beta

        let raw = virtualPointer ?? mouseLocation()
        if let last = lastRaw {
            let jump = hypot(raw.x - last.x, raw.y - last.y)
            if jump > 0.5 { lastMoveTime = now }
            // Teleport (e.g. cursor moved to another display): don't sweep across.
            if jump > 600 {
                filter.reset()
                trail.removeAll()
            }
        }
        lastRaw = raw

        let target: CGFloat
        switch s.mode {
        case .off: target = 0
        case .always: target = 1
        case .hold: target = buttonHeld ? 1 : 0
        case .moving: target = (buttonHeld || (now - lastMoveTime) < s.idleDelay) ? 1 : 0
        }

        // Fade in quickly, fade out gently.
        let rate: CGFloat = target > opacity ? 1 / 0.06 : 1 / 0.35
        let step = rate * dt
        opacity = target > opacity ? min(target, opacity + step) : max(target, opacity - step)

        if opacity <= 0 {
            filter.reset()
            trail.removeAll()
            position = raw
            if parkedAt == nil { virtualPointer = nil }   // faded out: follow the cursor again
        } else {
            position = filter.filter(raw, time: now)
            if let last = trail.last, hypot(position.x - last.point.x, position.y - last.point.y) < 0.05 {
                // Not moving: don't grow the tail with duplicate points.
            } else {
                trail.append(TrailPoint(point: position, time: now))
            }
            let cutoff = now - s.trailDuration
            if let firstFresh = trail.firstIndex(where: { $0.time >= cutoff }) {
                // Keep one older point so the tail starts smoothly.
                if firstFresh > 1 { trail.removeFirst(firstFresh - 1) }
            } else {
                trail.removeAll()
            }
        }

        CursorHider.setHidden(s.hideCursor && opacity > 0)
        CursorHider.track(cursor: mouseLocation())

        // Nothing left to animate: stop the display links until the mouse
        // moves again or a setting changes. Covers "laser hidden" and
        // "laser shown but the dot has caught up with a still cursor".
        let hiddenForGood = opacity == 0 && target == 0
        let settled = opacity == target && trail.isEmpty
            && hypot(position.x - raw.x, position.y - raw.y) < 0.05
        if hiddenForGood || settled {
            pauseAll()
        }
    }
}
