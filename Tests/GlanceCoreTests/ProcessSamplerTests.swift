import XCTest
@testable import GlanceCore

private final class StubProcSource: RawProcessSource {
    var queue: [[RawProcess]]
    init(_ q: [[RawProcess]]) { queue = q }
    func read() -> [RawProcess]? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class ProcessSamplerTests: XCTestCase {
    func testComputesCPUFractionFromDelta() {
        // pid 1:1 秒內 cpu 時間 +0.5s → 0.5;pid 2:+0.1s → 0.1
        let first = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.0, memoryBytes: 200),
        ]
        let second = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.5, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.1, memoryBytes: 200),
        ]
        var times = [0.0, 1.0]
        let sampler = ProcessSampler(source: StubProcSource([first, second]),
                                     clock: { times.removeFirst() }, limit: 5)
        _ = sampler.sampleTopByCPU()
        let top = sampler.sampleTopByCPU()
        XCTAssertEqual(top.first?.pid, 1)
        XCTAssertEqual(top.first?.cpuFraction ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(top.first?.name, "A")
    }

    func testNewProcessHasZeroCPUUntilSecondSample() {
        let first = [RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100)]
        var times = [0.0]
        let sampler = ProcessSampler(source: StubProcSource([first]),
                                     clock: { times.removeFirst() }, limit: 5)
        let top = sampler.sampleTopByCPU()
        XCTAssertEqual(top.first?.cpuFraction, 0)
    }
}
