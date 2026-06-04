import XCTest
@testable import GlanceCore

final class MenuBarDisplayModeTests: XCTestCase {
    func testRawValueRoundTripsForStoredValues() {
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconValue"), .iconValue)
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconOnly"), .iconOnly)
    }

    func testIconOnlyRawValueRemainsStableForStatusIconMode() {
        XCTAssertEqual(MenuBarDisplayMode.iconOnly.rawValue, "iconOnly")
    }

    func testAllCasesOrder() {
        XCTAssertEqual(MenuBarDisplayMode.allCases, [.iconValue, .iconOnly])
    }
}
