import XCTest
@testable import GlanceCore

private final class StubCPUSource: CPUTicksSource {
    var queue: [CPUTicks]
    init(_ q: [CPUTicks]) { queue = q }
    func read() -> CPUTicks? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class CPUSamplerTests: XCTestCase {
    func testFirstSampleIsZero() {
        let src = StubCPUSource([CPUTicks(user: 100, system: 50, idle: 850, nice: 0)])
        let sampler = CPUSampler(source: src)
        let snap = sampler.sample()
        XCTAssertEqual(snap?.totalUsage, 0)
    }

    func testSecondSampleComputesUsageFromDelta() {
        // delta: user+50, system+20, idle+930, nice+0 → total 1000, busy 70 → 7%
        let src = StubCPUSource([
            CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUTicks(user: 150, system: 70, idle: 1780, nice: 0),
        ])
        let sampler = CPUSampler(source: src)
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.totalUsage ?? -1, 0.07, accuracy: 0.0001)
        XCTAssertEqual(snap?.system ?? -1, 0.02, accuracy: 0.0001)
    }

    func testReturnsNilWhenSourceFails() {
        let src = StubCPUSource([])
        XCTAssertNil(CPUSampler(source: src).sample())
    }
}
