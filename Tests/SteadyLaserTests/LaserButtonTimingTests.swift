import XCTest
@testable import SteadyLaser

/// Tap / hold / double-press handling in `LaserController`, driven by a fake
/// clock. "Remote press" = the Norwii pointer's ⌃L … ⌃A: two quick taps,
/// each a press immediately followed by a release.
@MainActor
final class LaserButtonTimingTests: XCTestCase {
    private var controller: LaserController!
    private var now: CFTimeInterval = 100
    private var doublePresses = 0

    override func setUp() async throws {
        controller = LaserController()
        now = 100
        doublePresses = 0
        controller.clock = { [unowned self] in self.now }
        controller.onDoublePress = { [unowned self] in self.doublePresses += 1 }
    }

    private func tap() {
        controller.laserButtonPressed()
        now += 0.02
        controller.laserButtonReleased()
    }

    /// One remote press shown for `shown` seconds (⌃L tap, wait, ⌃A tap).
    private func remotePress(shown: CFTimeInterval) {
        tap()
        XCTAssertTrue(controller.buttonHeld, "⌃L should show the laser")
        now += shown
        tap()
        XCTAssertFalse(controller.buttonHeld, "⌃A should hide the laser")
    }

    func testTapLatchesAndNextTapHides() {
        tap()
        now += 3
        XCTAssertTrue(controller.buttonHeld)
        tap()
        XCTAssertFalse(controller.buttonHeld)
    }

    func testLongHoldHidesOnRelease() {
        controller.laserButtonPressed()
        now += 1
        XCTAssertTrue(controller.buttonHeld)
        controller.laserButtonReleased()
        XCTAssertFalse(controller.buttonHeld)
    }

    /// Timings logged from the real remote: shown ~0.7 s, next press ~0.7 s later.
    func testTwoRemotePressesSwitch() {
        remotePress(shown: 0.7)
        now += 0.7
        remotePress(shown: 1.5)
        XCTAssertEqual(doublePresses, 1)
    }

    func testThirdPressStartsOver() {
        remotePress(shown: 0.5)
        now += 0.8
        remotePress(shown: 0.5)
        now += 0.8
        remotePress(shown: 0.5)
        XCTAssertEqual(doublePresses, 1, "press 3 alone isn't a double press")
        now += 0.8
        remotePress(shown: 0.5)
        XCTAssertEqual(doublePresses, 2, "presses 3 and 4 are")
    }

    /// Faster than ~0.5 s is the remote's own double click (it switches the
    /// remote's mode), so the app must not count it.
    func testFastSecondPressIsLeftToTheRemote() {
        remotePress(shown: 0.5)
        now += 0.3
        remotePress(shown: 0.5)
        XCTAssertEqual(doublePresses, 0)
    }

    /// The remote holds back ⌃A for up to a second after a short press, so a
    /// "short" first press can show for 1.6 s.
    func testFirstPressShownUpToAboutOneAndAHalfSecondsCounts() {
        remotePress(shown: 1.6)
        now += 0.8
        remotePress(shown: 0.8)
        XCTAssertEqual(doublePresses, 1)
    }

    func testSlowRhythmUpToOneAndAHalfSeconds() {
        remotePress(shown: 0.6)
        now += 1.4
        remotePress(shown: 0.6)
        XCTAssertEqual(doublePresses, 1)
        now += 3
        remotePress(shown: 0.6)
        now += 1.8
        remotePress(shown: 0.6)
        XCTAssertEqual(doublePresses, 1, "a pause of 1.8 s is two separate presses")
    }

    func testNormalPointingDoesNotSwitch() {
        remotePress(shown: 2.5)       // pointing at something
        now += 0.5
        remotePress(shown: 2.0)       // a long first press doesn't count
        now += 3
        remotePress(shown: 0.5)       // a gap over a second doesn't count
        XCTAssertEqual(doublePresses, 0)
    }

    func testResetForgetsTheLastPress() {
        remotePress(shown: 0.5)
        controller.resetLaserButton()
        now += 0.8
        remotePress(shown: 0.5)
        XCTAssertEqual(doublePresses, 0)
    }
}
