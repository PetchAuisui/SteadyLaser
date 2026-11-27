import AppKit
import QuartzCore

/// Opt-in trace for checking a remote and cursor hiding on a real machine:
///
///     defaults write local.steadylaser debugLog -bool true
///
/// then restart the app and read `~/Library/Logs/SteadyLaser.log`.
enum DebugLog {
    static let enabled = UserDefaults.standard.bool(forKey: "debugLog")
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SteadyLaser.log")

    static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = String(format: "%.3f ", CACurrentMediaTime()) + message() + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: false, encoding: .utf8)
        }
    }
}
