import XCTest
@testable import SteadyLaser

/// The spotlight circle has its own size, no longer tied to the laser size.
final class SpotlightSizeTests: XCTestCase {
    func testSizesGrowInMenuOrder() {
        let radii = SpotlightSize.allCases.map(\.radius)
        XCTAssertEqual(radii, radii.sorted())
        XCTAssertEqual(Set(radii).count, radii.count)
    }

    /// Someone who had picked a laser size keeps the spotlight circle they had.
    func testStartsFromTheCircleTheLaserSizeGave() {
        XCTAssertEqual(SpotlightSize(matching: .small).radius, 90)
        XCTAssertEqual(SpotlightSize(matching: .medium).radius, 135)
        XCTAssertEqual(SpotlightSize(matching: .large).radius, 195)
    }
}
