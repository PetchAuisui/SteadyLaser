import XCTest
@testable import SteadyLaser

/// The spotlight circle has its own size, no longer tied to the laser size,
/// and its own shade outside the circle.
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

    func testShadesDarkenInMenuOrder() {
        let alphas = SpotlightShade.allCases.map(\.alpha)
        XCTAssertEqual(alphas, alphas.sorted())
        XCTAssertEqual(Set(alphas).count, alphas.count)
        XCTAssertTrue(alphas.allSatisfy { $0 > 0 && $0 < 1 }, "the slide must stay a little visible")
    }

    /// The shade the spotlight always had stays the default.
    func testMediumShadeIsTheOldShade() {
        XCTAssertEqual(SpotlightShade.medium.alpha, 0.7)
        XCTAssertEqual(SpotlightShade.medium.title, "กลาง (70%)")
    }
}
