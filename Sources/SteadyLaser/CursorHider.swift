import AppKit
import Darwin

/// Hides the system cursor while the laser is showing.
///
/// A background (menu bar) app can't normally hide the cursor, so we set the
/// WindowServer connection property "SetsCursorInBackground" first. That is a
/// private API, looked up with dlsym: if it's missing on some macOS version,
/// hiding just doesn't happen and the cursor stays visible.
@MainActor
enum CursorHider {
    private static var isHidden = false
    private static var backgroundAllowed = false

    private static func allowBackgroundHiding() {
        guard !backgroundAllowed else { return }
        backgroundAllowed = true

        typealias ConnectionFn = @convention(c) () -> Int32
        typealias SetPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard
            let connSym = dlsym(rtldDefault, "_CGSDefaultConnection") ?? dlsym(rtldDefault, "CGSMainConnectionID"),
            let setSym = dlsym(rtldDefault, "CGSSetConnectionProperty")
        else {
            DebugLog.write("cursor: private API missing")
            return
        }

        let connection = unsafeBitCast(connSym, to: ConnectionFn.self)()
        let setProperty = unsafeBitCast(setSym, to: SetPropertyFn.self)
        let err = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        DebugLog.write("cursor: connection \(connection) SetsCursorInBackground -> \(err)")
    }

    static func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden {
            allowBackgroundHiding()
            observeAppSwitches()
            let err = CGDisplayHideCursor(CGMainDisplayID())
            wasOverSystemUI = isOverSystemUI(NSEvent.mouseLocation)
            DebugLog.write("cursor: hide -> \(err.rawValue), front app \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        } else {
            let err = CGDisplayShowCursor(CGMainDisplayID())
            DebugLog.write("cursor: show -> \(err.rawValue)")
        }
        isHidden = hidden
    }

    // MARK: Staying hidden

    /// The Dock and the menu bar show the cursor while it's over them, and it
    /// stays visible after it leaves; so does switching apps. Hiding again
    /// from the visible state (show, then hide) brings it back to hidden.
    private static func rehide(_ reason: String) {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        let err = CGDisplayHideCursor(CGMainDisplayID())
        DebugLog.write("cursor: re-hide after \(reason) -> \(err.rawValue)")
    }

    private static var wasOverSystemUI = false

    /// Called with the cursor position every frame the laser is drawn.
    static func track(cursor p: CGPoint) {
        guard isHidden else { return }
        let over = isOverSystemUI(p)
        if wasOverSystemUI && !over { rehide("Dock / menu bar") }
        wasOverSystemUI = over
    }

    /// Whether `p` is where the Dock or the menu bar can be: the band they
    /// take on their screen edge, at least `dockBand` / `menuBand` deep so an
    /// auto-hidden Dock or menu bar (no inset in `visibleFrame`) counts too.
    static func isOverSystemUI(_ p: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        let f = screen.frame, v = screen.visibleFrame
        let dockBand: CGFloat = 130, menuBand: CGFloat = 30
        if p.y > f.maxY - max(f.maxY - v.maxY, menuBand) { return true }
        switch dockEdge {
        case "left": return p.x < f.minX + max(v.minX - f.minX, dockBand)
        case "right": return p.x > f.maxX - max(f.maxX - v.maxX, dockBand)
        default: return p.y < f.minY + max(v.minY - f.minY, dockBand)
        }
    }

    /// Which screen edge the Dock is on ("bottom", "left" or "right").
    static let dockEdge = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"

    // MARK: Keeping the cursor off the Dock and menu bar

    /// Where the cursor may go while the laser button shows the laser: the
    /// screen minus the Dock and the menu bar (`visibleFrame`), and never the
    /// last few points of the Dock edge or the top edge, where an auto-hidden
    /// Dock or menu bar (full-screen slideshow) would pop up. The Dock and the
    /// menu bar react to the cursor itself, under any window, so the overlay
    /// taking the mouse isn't enough there.
    nonisolated static func pointerArea(frame f: CGRect, visibleFrame v: CGRect, dockEdge: String) -> CGRect {
        let edge: CGFloat = 3
        var minX = f.minX, maxX = f.maxX, minY = f.minY
        let maxY = min(v.maxY, f.maxY - edge)
        switch dockEdge {
        case "left": minX = max(v.minX, f.minX + edge)
        case "right": maxX = min(v.maxX, f.maxX - edge)
        default: minY = max(v.minY, f.minY + edge)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps a cursor inside `area` onto the whole `frame`, so the laser still
    /// reaches the Dock and the menu bar while the cursor stays off them. The
    /// cursor is hidden, so the small stretch (~12% with a 70 pt Dock, almost
    /// none in a full-screen slideshow) doesn't show.
    nonisolated static func laserPoint(for p: CGPoint, area r: CGRect, frame f: CGRect) -> CGPoint {
        guard r.width > 0, r.height > 0 else { return p }
        return CGPoint(x: f.minX + (p.x - r.minX) * f.width / r.width,
                       y: f.minY + (p.y - r.minY) * f.height / r.height)
    }

    /// For a cursor at `p` while the laser button shows the laser: where to
    /// put the cursor back to if it left its screen's `pointerArea` (nil if
    /// it didn't), and where to draw the laser.
    static func keepOffSystemUI(_ p: CGPoint) -> (cursor: CGPoint?, laser: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return (nil, p) }
        let r = pointerArea(frame: screen.frame, visibleFrame: screen.visibleFrame, dockEdge: dockEdge)
        let inside = CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
        return (inside == p ? nil : inside, laserPoint(for: inside, area: r, frame: screen.frame))
    }

    /// Moves the cursor to `p` (AppKit global coordinates).
    static func warp(to p: CGPoint) {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: primaryTop - p.y))
        // Without this, real mouse moves are held back for a moment after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static var appSwitchObserver: NSObjectProtocol?

    private static func observeAppSwitches() {
        guard appSwitchObserver == nil else { return }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { rehide("app switch") }
        }
    }
}
