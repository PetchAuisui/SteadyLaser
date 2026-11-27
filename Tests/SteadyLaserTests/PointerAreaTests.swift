import XCTest
@testable import SteadyLaser

/// While the laser button shows the laser, the cursor stays out of the Dock
/// and the menu bar, which react to the cursor under any window.
final class PointerAreaTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testDockAtTheBottomAndMenuBar() {
        // Dock 70 pt high at the bottom, menu bar 33 pt at the top.
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)
        XCTAssertEqual(CursorHider.pointerArea(frame: frame, visibleFrame: visible, dockEdge: "bottom"),
                       CGRect(x: 0, y: 70, width: 1512, height: 879))
    }

    /// Full-screen slideshow: Dock and menu bar hidden. Keep a thin strip at
    /// the Dock edge and the top so neither pops up; the rest is usable.
    func testFullScreenKeepsTheEdgesThatRevealThem() {
        let area = CursorHider.pointerArea(frame: frame, visibleFrame: frame, dockEdge: "bottom")
        XCTAssertEqual(area, CGRect(x: 0, y: 3, width: 1512, height: 976))
    }

    func testDockOnTheLeft() {
        let visible = CGRect(x: 64, y: 0, width: 1448, height: 949)
        let area = CursorHider.pointerArea(frame: frame, visibleFrame: visible, dockEdge: "left")
        XCTAssertEqual(area.minX, 64)
        XCTAssertEqual(area.minY, 0, "the bottom edge is free when the Dock is on the left")
        XCTAssertEqual(area.maxY, 949)
    }

    /// A second display offset from the primary keeps its own coordinates.
    func testSecondDisplay() {
        let f = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let area = CursorHider.pointerArea(frame: f, visibleFrame: f, dockEdge: "bottom")
        XCTAssertEqual(area, CGRect(x: 1512, y: -197, width: 1920, height: 1074))
    }

    // MARK: Laser mapped over the whole screen

    func testCornersOfTheAreaReachTheCornersOfTheScreen() {
        let area = CGRect(x: 0, y: 70, width: 1512, height: 879)   // Dock below, menu bar above
        XCTAssertEqual(CursorHider.laserPoint(for: CGPoint(x: 0, y: 70), area: area, frame: frame), CGPoint(x: 0, y: 0),
                       "cursor at the Dock wall: laser at the very bottom, over the Dock")
        XCTAssertEqual(CursorHider.laserPoint(for: CGPoint(x: 1512, y: 949), area: area, frame: frame), CGPoint(x: 1512, y: 982),
                       "cursor under the menu bar: laser at the very top")
    }

    func testMiddleStaysPutAndXIsUntouchedWithTheDockBelow() {
        let area = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let p = CursorHider.laserPoint(for: CGPoint(x: 700, y: 509.5), area: area, frame: frame)
        XCTAssertEqual(p.x, 700)
        XCTAssertEqual(p.y, 491, accuracy: 0.01)
    }

    func testFullAreaIsIdentity() {
        XCTAssertEqual(CursorHider.laserPoint(for: CGPoint(x: 123, y: 456), area: frame, frame: frame), CGPoint(x: 123, y: 456))
    }
}
