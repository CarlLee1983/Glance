import XCTest
@testable import GlanceCore

final class MenuBarTextTests: XCTestCase {
    private var snap: SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.23, user: 0.23, system: 0, idle: 0.77),
            memory: MemorySnapshot(usedBytes: 61, totalBytes: 100, swapUsedBytes: 0, pressure: .normal),
            network: NetworkSnapshot(downBytesPerSec: 2_202_009, upBytesPerSec: 0, totalDownBytes: 0, totalUpBytes: 0),
            disk: nil, battery: nil, topByCPU: [], topByMemory: [])
    }

    func testComposesSelectedSegmentsInOrder() {
        let s = MenuBarText.compose(snapshot: snap, segments: [.cpu, .memory, .network])
        XCTAssertEqual(s, "23% · 61% · ↓2.1M")
    }

    func testSubsetOnly() {
        XCTAssertEqual(MenuBarText.compose(snapshot: snap, segments: [.cpu]), "23%")
    }

    func testNilSnapshotShowsDash() {
        XCTAssertEqual(MenuBarText.compose(snapshot: nil, segments: [.cpu]), "—")
    }

    func testEmptySegmentsShowsDash() {
        XCTAssertEqual(MenuBarText.compose(snapshot: snap, segments: []), "—")
    }
}
