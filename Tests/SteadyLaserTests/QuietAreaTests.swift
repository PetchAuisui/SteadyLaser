import XCTest
@testable import SteadyLaser

/// Over the settings window the laser stays hidden, so the spotlight doesn't
/// dim the window while it's being used, unless the laser button shows it.
@MainActor
final class QuietAreaTests: XCTestCase {
    private var controller: LaserController!

    override func setUp() async throws {
        Settings.shared.mode = .always
        Settings.shared.hideCursor = false      // leave the test runner's cursor alone
        Settings.shared.detachCursor = false
        controller = LaserController()
    }

    override func tearDown() async throws {
        for key in ["laserMode", "lastActiveMode", "hideCursor", "detachCursor"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func runFrames() {
        for frame in 1...5 { controller.update(now: Double(frame) * 0.1) }
    }

    func testShowsOutsideTheSettingsWindow() {
        controller.quietArea = { .null }
        runFrames()
        XCTAssertEqual(controller.opacity, 1)
    }

    func testHiddenOverTheSettingsWindow() {
        controller.quietArea = { .infinite }
        runFrames()
        XCTAssertEqual(controller.opacity, 0)
    }

    func testTheLaserButtonStillShowsIt() {
        controller.quietArea = { .infinite }
        controller.laserButtonPressed()
        runFrames()
        XCTAssertEqual(controller.opacity, 1)
    }
}
