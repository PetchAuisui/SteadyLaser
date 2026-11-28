import XCTest
@testable import SteadyLaser

/// `--snapshot-settings` sets up the window on settings of its own; they must
/// never reach the user's.
@MainActor
final class SettingsDefaultsTests: XCTestCase {
    private let domain = "local.steadylaser.tests"

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    func testOtherDefaultsLeaveTheUsersSettingsAlone() throws {
        let own = try XCTUnwrap(UserDefaults(suiteName: domain))
        let before = Settings.shared.spotlightShade
        let other = Settings(defaults: own)
        other.spotlightShade = before == .darkest ? .lightest : .darkest
        XCTAssertNotEqual(other.spotlightShade, before)
        XCTAssertEqual(Settings.shared.spotlightShade, before)
    }
}
