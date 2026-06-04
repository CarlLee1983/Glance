import XCTest
@testable import GlanceCore

final class MenuBarTextTests: XCTestCase {
    private func makeSnapshot(disk: DiskSnapshot? = nil, battery: BatteryStats? = nil) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.23, user: 0.23, system: 0, idle: 0.77),
            memory: MemorySnapshot(usedBytes: 61, totalBytes: 100, swapUsedBytes: 0, pressure: .normal),
            network: NetworkSnapshot(downBytesPerSec: 2_202_009, upBytesPerSec: 0, totalDownBytes: 0, totalUpBytes: 0),
            disk: disk, battery: battery, topByCPU: [], topByMemory: [])
    }

    func testReadingsFollowSegmentOrder() {
        let r = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.network, .cpu, .memory])
        XCTAssertEqual(r, [
            SegmentReading(segment: .network, value: "2.1M"),
            SegmentReading(segment: .cpu, value: "23%"),
            SegmentReading(segment: .memory, value: "61%"),
        ])
    }

    func testDiskAndBatteryReadings() {
        let snap = makeSnapshot(
            disk: DiskSnapshot(totalBytes: 100, usedBytes: 71),
            battery: BatteryStats(isPresent: true, chargeFraction: 0.99, isCharging: false))
        let r = MenuBarText.readings(snapshot: snap, segments: [.disk, .battery])
        XCTAssertEqual(r, [
            SegmentReading(segment: .disk, value: "71%"),
            SegmentReading(segment: .battery, value: "99%"),
        ])
    }

    func testAbsentBatteryIsSkipped() {
        let snap = makeSnapshot(battery: BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false))
        XCTAssertEqual(MenuBarText.readings(snapshot: snap, segments: [.battery]), [])
    }

    func testMissingMetricIsSkipped() {
        let r = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.cpu, .disk])
        XCTAssertEqual(r, [SegmentReading(segment: .cpu, value: "23%")])
    }

    func testNilSnapshotReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: nil, segments: [.cpu]), [])
    }

    func testEmptySegmentsReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: makeSnapshot(), segments: []), [])
    }

    func testDisplayModeRoundTrips() {
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconOnly"), .iconOnly)
        XCTAssertEqual(MenuBarDisplayMode.allCases, [.iconValue, .iconOnly])
    }
}
