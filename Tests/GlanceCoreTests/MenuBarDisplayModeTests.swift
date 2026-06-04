import XCTest
@testable import GlanceCore

final class MenuBarDisplayModeTests: XCTestCase {
    func testRawValueRoundTrips() {
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconValue"), .iconValue)
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconOnly"), .iconOnly)
    }
}
