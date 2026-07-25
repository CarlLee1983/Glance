import XCTest
@testable import GlanceCore

private final class StubMemSource: RawProcessSource {
    let procs: [RawProcess]
    init(_ p: [RawProcess]) { procs = p }
    func read() -> [RawProcess]? { procs }
}

final class ProcessSamplerMemoryAppsTests: XCTestCase {
    func testNonAppProcessesWithSamePathAreAggregated() {
        // 同一執行檔路徑的多個非 .app 行程,聚合成一列(比照 .app 的彙總規則),
        // 記憶體加總、processCount 反映實際行程數,並以路徑為群組鍵。
        let procs = [
            RawProcess(pid: 100, name: "node", cpuTimeSeconds: 0, memoryBytes: 1_300, executablePath: "/usr/local/bin/node"),
            RawProcess(pid: 101, name: "node", cpuTimeSeconds: 0, memoryBytes: 170, executablePath: "/usr/local/bin/node"),
            RawProcess(pid: 102, name: "node", cpuTimeSeconds: 0, memoryBytes: 40, executablePath: "/usr/local/bin/node"),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps

        XCTAssertEqual(apps.count, 1)
        let node = apps[0]
        XCTAssertEqual(node.appName, "node")
        XCTAssertEqual(node.memoryBytes, 1_510)
        XCTAssertEqual(node.processCount, 3)
        XCTAssertNil(node.bundleURL)
        XCTAssertEqual(node.kind, .userProcess)
        XCTAssertEqual(node.executablePath, "/usr/local/bin/node")
        XCTAssertEqual(node.id, "/usr/local/bin/node")
        // 多行程群組沒有單一 pid 可指認
        XCTAssertNil(node.soloPID)
    }

    func testNonAppProcessesWithDifferentPathsStaySeparate() {
        // 不同執行檔路徑不可被誤加總,即使同名。
        let procs = [
            RawProcess(pid: 1, name: "node", cpuTimeSeconds: 0, memoryBytes: 500, executablePath: "/usr/local/bin/node"),
            RawProcess(pid: 2, name: "node", cpuTimeSeconds: 0, memoryBytes: 400, executablePath: "/opt/homebrew/bin/node"),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(Set(apps.map(\.id)).count, 2)
        XCTAssertTrue(apps.allSatisfy { $0.processCount == 1 })
        // 單行程群組保留可指認的 pid
        XCTAssertEqual(apps.first { $0.executablePath == "/usr/local/bin/node" }?.soloPID, 1)
    }

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

        // 巢狀 .app(helper)歸為 App 子行程,而非可獨立結束的 App。
        let helper = apps.first { $0.appName == "Google Chrome Helper" }
        XCTAssertEqual(helper?.memoryBytes, 5_000)
        XCTAssertEqual(helper?.processCount, 2)
        XCTAssertEqual(helper?.kind, .appChild)
        XCTAssertNil(helper?.soloPID)

        // 頂層 .app 單一行程 → 是 App,且保留可指認 pid。
        let xcode = apps.first { $0.appName == "Xcode" }
        XCTAssertEqual(xcode?.kind, .app)
        XCTAssertEqual(xcode?.soloPID, 4)

        XCTAssertEqual(apps.first?.appName, "Google Chrome Helper")
        XCTAssertEqual(apps.first?.memoryBytes, 5_000)
    }

    func testClassifiesSystemServiceUserProcessAndUnknown() {
        let procs = [
            RawProcess(pid: 10, name: "cfprefsd", cpuTimeSeconds: 0, memoryBytes: 500, executablePath: "/usr/sbin/cfprefsd"),
            RawProcess(pid: 11, name: "launchd", cpuTimeSeconds: 0, memoryBytes: 700, executablePath: nil),
            RawProcess(pid: 12, name: "ovpnagent", cpuTimeSeconds: 0, memoryBytes: 600, executablePath: "/Library/Frameworks/OpenVPNConnect.framework/Versions/Current/usr/sbin/ovpnagent"),
        ]
        let sampler = ProcessSampler(source: StubMemSource(procs), clock: { 0 }, limit: 5)
        let apps = sampler.sample().topMemoryApps

        let launchd = apps.first { $0.appName == "launchd" }
        XCTAssertEqual(launchd?.kind, .unknown)
        XCTAssertEqual(launchd?.soloPID, 11)
        XCTAssertNil(launchd?.executablePath)

        let service = apps.first { $0.appName == "cfprefsd" }
        XCTAssertEqual(service?.kind, .systemService)
        XCTAssertEqual(service?.soloPID, 10)
        XCTAssertEqual(service?.executablePath, "/usr/sbin/cfprefsd")

        // 第三方 framework 內的 daemon 不在 Apple 系統目錄 → 使用者背景程式(非「命令列」)。
        let ovpn = apps.first { $0.appName == "ovpnagent" }
        XCTAssertEqual(ovpn?.kind, .userProcess)
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
