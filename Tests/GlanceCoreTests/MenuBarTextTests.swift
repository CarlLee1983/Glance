import XCTest
@testable import GlanceCore

final class MenuBarTextTests: XCTestCase {
    private func makeSnapshot(
        cpuUsage: Double = 0.23,
        memoryUsedFraction: Double = 0.61,
        networkDownBytesPerSec: Double = 2_202_009,
        disk: DiskSnapshot? = nil,
        battery: BatteryStats? = nil
    ) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpuUsage, user: cpuUsage, system: 0, idle: 1 - cpuUsage),
            memory: MemorySnapshot(
                usedBytes: UInt64(memoryUsedFraction * 100),
                totalBytes: 100,
                swapUsedBytes: 0,
                pressure: .normal
            ),
            network: NetworkSnapshot(
                downBytesPerSec: networkDownBytesPerSec,
                upBytesPerSec: 0,
                totalDownBytes: 0,
                totalUpBytes: 0
            ),
            disk: disk,
            battery: battery,
            topByCPU: [],
            topByMemory: []
        )
    }

    func testReadingsFollowSegmentOrderAndIncludeStatus() {
        let readings = MenuBarText.readings(
            snapshot: makeSnapshot(cpuUsage: 0.91, memoryUsedFraction: 0.82),
            segments: [.network, .cpu, .memory]
        )

        XCTAssertEqual(readings, [
            SegmentReading(segment: .network, value: "2.1M", status: .normal),
            SegmentReading(segment: .cpu, value: "91%", status: .critical),
            SegmentReading(segment: .memory, value: "82%", status: .elevated),
        ])
    }

    func testDiskAndBatteryReadingsIncludeStatus() {
        let snapshot = makeSnapshot(
            disk: DiskSnapshot(totalBytes: 100, usedBytes: 93),
            battery: BatteryStats(isPresent: true, chargeFraction: 0.18, isCharging: false)
        )

        let readings = MenuBarText.readings(snapshot: snapshot, segments: [.disk, .battery])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .disk, value: "93%", status: .critical),
            SegmentReading(segment: .battery, value: "18%", status: .critical),
        ])
    }

    func testChargingBatteryUsesChargingStatus() {
        let snapshot = makeSnapshot(
            battery: BatteryStats(isPresent: true, chargeFraction: 0.81, isCharging: true)
        )

        let readings = MenuBarText.readings(snapshot: snapshot, segments: [.battery])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .battery, value: "81%", status: .charging),
        ])
    }

    func testAbsentBatteryIsSkipped() {
        let snapshot = makeSnapshot(
            battery: BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        )

        XCTAssertEqual(MenuBarText.readings(snapshot: snapshot, segments: [.battery]), [])
    }

    func testMissingMetricIsSkipped() {
        let readings = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.cpu, .disk])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .cpu, value: "23%", status: .normal),
        ])
    }

    func testNilSnapshotReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: nil, segments: [.cpu]), [])
    }

    func testEmptySegmentsReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: makeSnapshot(), segments: []), [])
    }
}
