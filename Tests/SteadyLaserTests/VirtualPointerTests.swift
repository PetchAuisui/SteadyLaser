import XCTest
@testable import SteadyLaser

/// While the laser button shows the laser, the real cursor stays parked and
/// only the laser moves, so the hidden cursor doesn't hover over anything.
@MainActor
final class VirtualPointerTests: XCTestCase {
    private var controller: LaserController!
    private var cursor = CGPoint(x: 300, y: 300)
    private var warps: [CGPoint] = []

    override func setUp() async throws {
        Settings.shared.detachCursor = true
        controller = LaserController()
        cursor = CGPoint(x: 300, y: 300)
        warps = []
        controller.mouseLocation = { [unowned self] in self.cursor }
        controller.warpCursor = { [unowned self] in self.warps.append($0) }
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "detachCursor")
    }

    private func press() { controller.laserButtonPressed(); controller.laserButtonReleased() }

    func testLaserMovesAndCursorStaysParked() {
        press()
        XCTAssertEqual(controller.parkedAt, CGPoint(x: 300, y: 300))
        controller.pointerMoved(dx: 10, dy: -5)    // right and up
        controller.pointerMoved(dx: 4, dy: 2)      // right and down
        XCTAssertEqual(controller.virtualPointer, CGPoint(x: 314, y: 303))
        XCTAssertEqual(warps, [CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 300)], "cursor put back after each move")
    }

    func testReleaseLetsTheCursorGo() {
        press()
        press()                                    // second tap: laser off
        XCTAssertNil(controller.parkedAt)
        controller.pointerMoved(dx: 10, dy: 0)
        XCTAssertTrue(warps.isEmpty)
    }

    func testNextPressCarriesOnFromTheLaser() {
        press()
        controller.pointerMoved(dx: 50, dy: 0)
        press()                                    // off
        press()                                    // on again, cursor hasn't moved
        XCTAssertEqual(controller.virtualPointer, CGPoint(x: 350, y: 300))
    }

    func testNextPressStartsAtACursorThatMoved() {
        press()
        controller.pointerMoved(dx: 50, dy: 0)
        press()                                    // off
        cursor = CGPoint(x: 120, y: 200)           // moved with the trackpad
        press()
        XCTAssertEqual(controller.virtualPointer, CGPoint(x: 120, y: 200))
        XCTAssertEqual(controller.parkedAt, CGPoint(x: 120, y: 200))
    }

    func testCanBeTurnedOff() {
        Settings.shared.detachCursor = false
        press()
        XCTAssertNil(controller.parkedAt)
        controller.pointerMoved(dx: 10, dy: 0)
        XCTAssertTrue(warps.isEmpty)
    }
}
