import XCTest
@testable import GlanceCore

final class MetricStatusTests: XCTestCase {
    func testLoadStatusBands() {
        XCTAssertEqual(MetricStatus.load(fraction: 0.42), .normal)
        XCTAssertEqual(MetricStatus.load(fraction: 0.76), .elevated)
        XCTAssertEqual(MetricStatus.load(fraction: 0.91), .critical)
    }

    func testCapacityStatusBands() {
        XCTAssertEqual(MetricStatus.capacity(fraction: 0.64), .normal)
        XCTAssertEqual(MetricStatus.capacity(fraction: 0.82), .elevated)
        XCTAssertEqual(MetricStatus.capacity(fraction: 0.93), .critical)
    }

    func testBatteryStatusUsesChargingAndLowCharge() {
        XCTAssertEqual(MetricStatus.battery(chargeFraction: 0.81, isCharging: true), .charging)
        XCTAssertEqual(MetricStatus.battery(chargeFraction: 0.18, isCharging: false), .critical)
        XCTAssertEqual(MetricStatus.battery(chargeFraction: 0.45, isCharging: false), .normal)
    }

    func testStatusLabelsAreStableForDropdownBadges() {
        XCTAssertEqual(MetricStatus.normal.label, "正常")
        XCTAssertEqual(MetricStatus.elevated.label, "偏高")
        XCTAssertEqual(MetricStatus.critical.label, "注意")
        XCTAssertEqual(MetricStatus.charging.label, "充電中")
    }
}
