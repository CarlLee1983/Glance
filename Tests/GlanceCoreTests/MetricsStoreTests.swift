import XCTest
@testable import GlanceCore

private final class StubSystemSampler: SystemSampling {
    var queue: [SystemSnapshot]
    init(_ q: [SystemSnapshot]) { queue = q }
    func sample() -> SystemSnapshot {
        queue.isEmpty
            ? SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
            : queue.removeFirst()
    }
}

final class MetricsStoreTests: XCTestCase {
    private func snap(cpu: Double) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpu, user: cpu, system: 0, idle: 1 - cpu),
            memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
    }

    func testTickUpdatesSnapshotAndHistory() {
        let store = MetricsStore(sampler: StubSystemSampler([snap(cpu: 0.1), snap(cpu: 0.2)]), historyCapacity: 90)
        store.tick()
        XCTAssertEqual(store.snapshot?.cpu?.totalUsage, 0.1)
        XCTAssertEqual(store.history.cpu.elements, [0.1])
        store.tick()
        XCTAssertEqual(store.snapshot?.cpu?.totalUsage, 0.2)
        XCTAssertEqual(store.history.cpu.elements, [0.1, 0.2])
    }
}
