import XCTest
@testable import GlanceCore

private struct StubMemorySource: MemoryStatsSource {
    let stats: MemoryStats?
    func read() -> MemoryStats? { stats }
}

final class MemorySamplerTests: XCTestCase {
    func testSnapshotComputesUsedFraction() {
        let stats = MemoryStats(
            totalBytes: 16_000_000_000,
            usedBytes: 9_760_000_000,
            swapUsedBytes: 200_000_000,
            pressure: .normal)
        let snap = MemorySampler(source: StubMemorySource(stats: stats)).sample()
        XCTAssertEqual(snap?.usedFraction ?? -1, 0.61, accuracy: 0.001)
        XCTAssertEqual(snap?.pressure, .normal)
    }

    func testReturnsNilWhenSourceFails() {
        XCTAssertNil(MemorySampler(source: StubMemorySource(stats: nil)).sample())
    }
}
