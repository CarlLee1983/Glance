import XCTest
@testable import GlanceCore

final class BatteryStatsTests: XCTestCase {
    func testAdvancedFieldsDefaultToNil() {
        let b = BatteryStats(isPresent: true, chargeFraction: 0.8, isCharging: false)
        XCTAssertNil(b.cycleCount)
        XCTAssertNil(b.healthFraction)
        XCTAssertNil(b.temperature)
        XCTAssertNil(b.powerWatts)
    }

    func testAdvancedFieldsArePreserved() {
        let b = BatteryStats(
            isPresent: true, chargeFraction: 0.8, isCharging: true,
            cycleCount: 142, healthFraction: 0.95, temperature: 31.2, powerWatts: 18.4)
        XCTAssertEqual(b.cycleCount, 142)
        XCTAssertEqual(b.healthFraction, 0.95)
        XCTAssertEqual(b.temperature, 31.2)
        XCTAssertEqual(b.powerWatts, 18.4)
    }
}
