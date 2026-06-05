import XCTest
@testable import GlanceCore

private final class StubProcSource2: RawProcessSource {
    var queue: [[RawProcess]]
    init(_ q: [[RawProcess]]) { queue = q }
    func read() -> [RawProcess]? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class ProcessSamplerCombinedTests: XCTestCase {
    func testSampleReturnsBothRankingsFromOneRead() {
        let first = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.0, memoryBytes: 9_000),
        ]
        let second = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.9, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.1, memoryBytes: 9_000),
        ]
        var times = [0.0, 1.0]
        let sampler = ProcessSampler(source: StubProcSource2([first, second]),
                                     clock: { times.removeFirst() }, limit: 5)
        _ = sampler.sample()          // baseline (consumes first)
        let result = sampler.sample() // consumes second
        XCTAssertEqual(result.topCPU.first?.name, "A")
        XCTAssertEqual(result.topCPU.first?.cpuFraction ?? -1, 0.9, accuracy: 0.001)
        XCTAssertEqual(result.topMemoryApps.first?.appName, "B")
    }
}
