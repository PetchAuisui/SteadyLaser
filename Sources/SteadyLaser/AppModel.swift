import AppKit
import ServiceManagement

/// What the menu and the settings window show besides `Settings`, and what
/// they can ask the app to do. AppDelegate fills in the actions and calls
/// `changed()` whenever anything shown here may have changed.
@MainActor
final class AppModel: ObservableObject {
    let settings = Settings.shared

    /// Why the laser button couldn't be bound, if it couldn't.
    var laserButtonError: String?

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    var learnLaserButton: () -> Void = {}
    var clearLaserButton: () -> Void = {}
    var toggleLaunchAtLogin: () -> Void = {}

    func changed() { objectWillChange.send() }
}
