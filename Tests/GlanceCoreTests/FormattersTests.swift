import XCTest
@testable import GlanceCore

final class FormattersTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(Formatters.percent(0.234), "23%")
        XCTAssertEqual(Formatters.percent(0), "0%")
        XCTAssertEqual(Formatters.percent(1), "100%")
    }

    func testPercentClampsAboveOne() {
        XCTAssertEqual(Formatters.percent(1.03), "100%")
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

    func testPercentLooseAllowsOverHundred() {
        XCTAssertEqual(Formatters.percentLoose(1.5), "150%")
        XCTAssertEqual(Formatters.percentLoose(0.02), "2%")
        XCTAssertEqual(Formatters.percentLoose(-0.1), "0%")
    }

    func testTemperatureFormatsWholeDegrees() {
        XCTAssertEqual(Formatters.temperature(52.4), "52°C")
        XCTAssertEqual(Formatters.temperature(47.6), "48°C")
    }

    func testWattsFormatsOneDecimal() {
        XCTAssertEqual(Formatters.watts(12.43), "12.4 W")
        XCTAssertEqual(Formatters.watts(3), "3.0 W")
        XCTAssertEqual(Formatters.watts(-8.2), "8.2 W")
    }
}
