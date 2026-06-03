import XCTest
@testable import GlanceCore

final class FormattersTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(Formatters.percent(0.234), "23%")
        XCTAssertEqual(Formatters.percent(0), "0%")
        XCTAssertEqual(Formatters.percent(1), "100%")
    }

    func testBytesGB() {
        XCTAssertEqual(Formatters.bytes(10_522_669_875), "9.8 GB")
    }

    func testBytesMB() {
        XCTAssertEqual(Formatters.bytes(5_242_880), "5.0 MB")
    }

    func testRateCompact() {
        XCTAssertEqual(Formatters.rateCompact(2_202_009), "2.1M")
        XCTAssertEqual(Formatters.rateCompact(3072), "3.0K")
        XCTAssertEqual(Formatters.rateCompact(0), "0")
    }
}
