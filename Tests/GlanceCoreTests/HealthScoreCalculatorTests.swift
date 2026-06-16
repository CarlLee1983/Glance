import XCTest
@testable import GlanceCore

final class HealthScoreCalculatorTests: XCTestCase {
    func testBandBoundaries() {
        XCTAssertEqual(HealthBand.from(score: 100), .excellent)
        XCTAssertEqual(HealthBand.from(score: 85), .excellent)
        XCTAssertEqual(HealthBand.from(score: 84), .good)
        XCTAssertEqual(HealthBand.from(score: 65), .good)
        XCTAssertEqual(HealthBand.from(score: 64), .fair)
        XCTAssertEqual(HealthBand.from(score: 45), .fair)
        XCTAssertEqual(HealthBand.from(score: 44), .needsAttention)
        XCTAssertEqual(HealthBand.from(score: 0), .needsAttention)
    }

    func testBandLabels() {
        XCTAssertEqual(HealthBand.excellent.label, "系統健康")
        XCTAssertEqual(HealthBand.good.label, "良好")
        XCTAssertEqual(HealthBand.fair.label, "普通")
        XCTAssertEqual(HealthBand.needsAttention.label, "注意")
    }
}
