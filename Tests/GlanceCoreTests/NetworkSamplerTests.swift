import XCTest
@testable import GlanceCore

private final class StubNetSource: NetworkCountersSource {
    var queue: [NetworkCounters]
    init(_ q: [NetworkCounters]) { queue = q }
    func read() -> NetworkCounters? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class NetworkSamplerTests: XCTestCase {
    func testFirstSampleHasZeroRate() {
        let src = StubNetSource([NetworkCounters(received: 1000, sent: 500)])
        let t = 0.0
        let snap = NetworkSampler(source: src, clock: { t }).sample()
        XCTAssertEqual(snap?.downBytesPerSec, 0)
        XCTAssertEqual(snap?.totalDownBytes, 1000)
    }

    func testSecondSampleComputesRate() {
        // +4_194_304 bytes 收 / 2 秒 = 2_097_152 B/s(2 MB/s)
        let src = StubNetSource([
            NetworkCounters(received: 1000, sent: 500),
            NetworkCounters(received: 1000 + 4_194_304, sent: 500 + 1_048_576),
        ])
        var times = [0.0, 2.0]
        let sampler = NetworkSampler(source: src, clock: { times.removeFirst() })
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.downBytesPerSec ?? -1, 2_097_152, accuracy: 1)
        XCTAssertEqual(snap?.upBytesPerSec ?? -1, 524_288, accuracy: 1)
    }
}
