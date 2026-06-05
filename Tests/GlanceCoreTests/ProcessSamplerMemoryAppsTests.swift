import XCTest
@testable import GlanceCore

private final class StubMemSource: RawProcessSource {
    let procs: [RawProcess]
    init(_ p: [RawProcess]) { procs = p }
    func read() -> [RawProcess]? { procs }
}

final class ProcessSamplerMemoryAppsTests: XCTestCase {
    func testSumsHelperProcessesUnderSameApp() {
        let chromeMain = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let procs = [
            RawProcess(pid: 1, name: "Google Chrome", cpuTimeSeconds: 0, memoryBytes: 1_000, executablePath: chromeMain),
            RawProcess(pid: 2, name: "Google Chrome Helper", cpuTimeSeconds: 0, memoryBytes: 3_000, executablePath: chromeHelper),
            RawProcess(pid: 3, name: "Google Chrome Helper", cpuTimeSeconds: 0, memoryBytes: 2_000, executablePath: chromeHelper),
            RawProcess(pid: 4, name: "Xcode", cpuTimeSeconds: 0, memoryBytes: 4_000, executablePath: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps

        let chromeBundle = apps.first { $0.appName == "Google Chrome Helper" }
        XCTAssertEqual(chromeBundle?.memoryBytes, 5_000)
        XCTAssertEqual(chromeBundle?.processCount, 2)

        XCTAssertEqual(apps.first?.appName, "Google Chrome Helper")
        XCTAssertEqual(apps.first?.memoryBytes, 5_000)
    }

    func testFallsBackToProcessNameWhenNoAppPath() {
        let procs = [
            RawProcess(pid: 10, name: "cfprefsd", cpuTimeSeconds: 0, memoryBytes: 500, executablePath: "/usr/sbin/cfprefsd"),
            RawProcess(pid: 11, name: "launchd", cpuTimeSeconds: 0, memoryBytes: 700, executablePath: nil),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps
        XCTAssertEqual(apps.first?.appName, "launchd")
        XCTAssertNil(apps.first?.bundleURL)
        XCTAssertEqual(apps.count, 2)
    }

    func testRespectsLimit() {
        let procs = (0..<10).map {
            RawProcess(pid: Int32($0), name: "p\($0)", cpuTimeSeconds: 0, memoryBytes: UInt64($0 * 100), executablePath: nil)
        }
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 3)
        XCTAssertEqual(sampler.sample().topMemoryApps.count, 3)
    }

    func testEqualMemoryAndNameAreOrderedDeterministicallyByKey() {
        // 同名(Helper)同記憶體、但不同 bundle 路徑 → 應以 groupKey(id)穩定排序
        let procs = [
            RawProcess(pid: 1, name: "Helper", cpuTimeSeconds: 0, memoryBytes: 1_000, executablePath: "/Y/Helper.app/Contents/MacOS/H"),
            RawProcess(pid: 2, name: "Helper", cpuTimeSeconds: 0, memoryBytes: 1_000, executablePath: "/X/Helper.app/Contents/MacOS/H"),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps
        XCTAssertEqual(apps.map(\.appName), ["Helper", "Helper"])
        XCTAssertEqual(apps.map(\.id), ["/X/Helper.app", "/Y/Helper.app"])
    }
}
