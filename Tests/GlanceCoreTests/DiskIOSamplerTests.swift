import XCTest
@testable import GlanceCore

private final class StubDiskIOSource: DiskIOStatsSource {
    var queue: [DiskIOCounters]
    init(_ q: [DiskIOCounters]) { queue = q }
    func read() -> DiskIOCounters? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class DiskIOSamplerTests: XCTestCase {
    func testFirstSampleHasZeroRate() {
        let src = StubDiskIOSource([DiskIOCounters(readBytes: 1000, writeBytes: 500)])
        let snap = DiskIOSampler(source: src, clock: { 0 }).sample()
        XCTAssertEqual(snap?.readBytesPerSec, 0)
        XCTAssertEqual(snap?.writeBytesPerSec, 0)
    }

    func testSecondSampleComputesRate() {
        let src = StubDiskIOSource([
            DiskIOCounters(readBytes: 1000, writeBytes: 500),
            DiskIOCounters(readBytes: 1000 + 4_194_304, writeBytes: 500 + 1_048_576),
        ])
        var times = [0.0, 2.0]
        let sampler = DiskIOSampler(source: src, clock: { times.removeFirst() })
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.readBytesPerSec ?? -1, 2_097_152, accuracy: 1)
        XCTAssertEqual(snap?.writeBytesPerSec ?? -1, 524_288, accuracy: 1)
    }

    func testNonPositiveIntervalReturnsZeroRate() {
        let src = StubDiskIOSource([
            DiskIOCounters(readBytes: 0, writeBytes: 0),
            DiskIOCounters(readBytes: 999, writeBytes: 999),
        ])
        let sampler = DiskIOSampler(source: src, clock: { 5 })
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.readBytesPerSec, 0)
        XCTAssertEqual(snap?.writeBytesPerSec, 0)
    }

    func testCounterWrapDoesNotCrash() {
        let src = StubDiskIOSource([
            DiskIOCounters(readBytes: 100, writeBytes: 100),
            DiskIOCounters(readBytes: 10, writeBytes: 10),
        ])
        var times = [0.0, 1.0]
        let sampler = DiskIOSampler(source: src, clock: { times.removeFirst() })
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertNotNil(snap)
    }

    func testReturnsNilWhenSourceFails() {
        let snap = DiskIOSampler(source: StubDiskIOSource([]), clock: { 0 }).sample()
        XCTAssertNil(snap)
    }
}
