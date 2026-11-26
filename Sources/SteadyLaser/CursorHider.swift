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
        else { return }

        let connection = unsafeBitCast(connSym, to: ConnectionFn.self)()
        let setProperty = unsafeBitCast(setSym, to: SetPropertyFn.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    static func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden {
            allowBackgroundHiding()
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            CGDisplayShowCursor(CGMainDisplayID())
        }
        isHidden = hidden
    }
}
