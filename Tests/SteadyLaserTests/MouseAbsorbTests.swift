import XCTest
@testable import SteadyLaser

/// While the laser button shows the laser, the overlay takes the mouse so the
/// hidden cursor doesn't hover or click anything underneath.
@MainActor
final class MouseAbsorbTests: XCTestCase {
    private var controller: LaserController!

    override func setUp() async throws {
        Settings.shared.detachCursor = true
        controller = LaserController()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "detachCursor")
    }

    private func tap() { controller.laserButtonPressed(); controller.laserButtonReleased() }

    func testTakesTheMouseOnlyWhileTheButtonShowsTheLaser() {
        XCTAssertFalse(controller.absorbsMouse)
        tap()                       // ⌃L: laser on
        XCTAssertTrue(controller.absorbsMouse)
        tap()                       // ⌃A: laser off
        XCTAssertFalse(controller.absorbsMouse)
    }

    func testCanBeTurnedOff() {
        Settings.shared.detachCursor = false
        tap()
        XCTAssertFalse(controller.absorbsMouse)
    }

    func testTurningItOffLetsGoRightAway() {
        tap()
        XCTAssertTrue(controller.absorbsMouse)
        Settings.shared.detachCursor = false
        controller.settingsChanged()
        XCTAssertFalse(controller.absorbsMouse)
    }

    func testResetLetsGo() {
        tap()
        controller.resetLaserButton()
        XCTAssertFalse(controller.absorbsMouse)
    }
}
