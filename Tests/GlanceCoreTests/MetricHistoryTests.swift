import XCTest
@testable import GlanceCore

final class MetricHistoryTests: XCTestCase {
    private func snapshot(cpu: Double, mem: Double, down: Double, up: Double, pressure: MemoryPressure = .normal) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpu, user: cpu, system: 0, idle: 1 - cpu),
            memory: MemorySnapshot(usedBytes: UInt64(mem * 100), totalBytes: 100, swapUsedBytes: 0, pressure: pressure),
            network: NetworkSnapshot(downBytesPerSec: down, upBytesPerSec: up, totalDownBytes: 0, totalUpBytes: 0),
            disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
    }

    func testRecordAppendsPerMetric() {
        var h = MetricHistory(capacity: 5)
        h.record(snapshot(cpu: 0.2, mem: 0.6, down: 1000, up: 50))
        h.record(snapshot(cpu: 0.3, mem: 0.61, down: 2000, up: 60))
        XCTAssertEqual(h.cpu.elements, [0.2, 0.3])
        XCTAssertEqual(h.memory.elements[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(h.memory.elements[1], 0.61, accuracy: 0.0001)
        XCTAssertEqual(h.netDown.elements, [1000, 2000])
        XCTAssertEqual(h.netUp.elements, [50, 60])
    }

    func testMissingMetricRecordsZero() {
        var h = MetricHistory(capacity: 5)
        let empty = SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
        h.record(empty)
        XCTAssertEqual(h.cpu.elements, [0])
        XCTAssertEqual(h.netDown.elements, [0])
    }

    func testRespectsCapacity() {
        var h = MetricHistory(capacity: 2)
        h.record(snapshot(cpu: 0.1, mem: 0, down: 0, up: 0))
        h.record(snapshot(cpu: 0.2, mem: 0, down: 0, up: 0))
        h.record(snapshot(cpu: 0.3, mem: 0, down: 0, up: 0))
        XCTAssertEqual(h.cpu.elements, [0.2, 0.3])
    }

    func testRecordsMemoryPressureLevel() {
        var h = MetricHistory(capacity: 5)
        h.record(snapshot(cpu: 0.2, mem: 0.6, down: 0, up: 0, pressure: .normal))
        h.record(snapshot(cpu: 0.2, mem: 0.8, down: 0, up: 0, pressure: .warning))
        h.record(snapshot(cpu: 0.2, mem: 0.95, down: 0, up: 0, pressure: .critical))
        XCTAssertEqual(h.memoryPressure.elements, [0, 1, 2])
    }

    func testMissingMemoryRecordsNormalPressure() {
        var h = MetricHistory(capacity: 5)
        let empty = SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
        h.record(empty)
        XCTAssertEqual(h.memoryPressure.elements, [0])
    }
}
