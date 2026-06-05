# 記憶體監控按 App 彙總 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Glance 記憶體排行從「單一行程」改為「按 app 彙總」,讓第一名反映整個 app(含 helper)的記憶體總和並在 UI 凸顯。

**Architecture:** 歸類與彙總邏輯放 `GlanceCore`(純公開 API `proc_pidpath`、可單元測試、不依賴 AppKit);app 圖示等呈現留 `GlanceApp`。範圍只含記憶體,CPU 清單不動。

**Tech Stack:** Swift 5.9、libproc(`proc_pidpath`)、Swift 值型別、XCTest、SwiftUI、AppKit(`NSWorkspace` 圖示)、XcodeGen。

---

## File Structure

- Create `Sources/GlanceCore/Sampling/AppGrouping.swift`
  - 純函式:執行檔路徑 → app 身分(groupKey / appName / bundleURL)。
- Create `Sources/GlanceCore/Model/AppMemoryUsage.swift`
  - 對外彙總值型別。
- Create `Tests/GlanceCoreTests/AppGroupingTests.swift`
  - AppGrouping 路徑歸類測試。
- Create `Tests/GlanceCoreTests/ProcessSamplerMemoryAppsTests.swift`
  - ProcessSampler 記憶體彙總測試。
- Create `GlanceApp/Components/AppMemoryList.swift`
  - 記憶體 app 排行清單(第一名凸顯 + 圖示)。
- Modify `Sources/GlanceCore/Model/ProcessUsage.swift`
  - `RawProcess` 加 `executablePath: String? = nil`。
- Modify `Sources/GlanceCore/Bridge/LibprocSource.swift`
  - 用 `proc_pidpath` 填 `executablePath`。
- Modify `Sources/GlanceCore/Sampling/ProcessSampler.swift`
  - `sample()` 改回傳 `(topCPU, topMemoryApps)`,加記憶體彙總。
- Modify `Sources/GlanceCore/SystemSnapshot.swift`
  - `topByMemory: [ProcessUsage]` → `topMemoryApps: [AppMemoryUsage]`。
- Modify `Sources/GlanceCore/Sampling/SystemSampler.swift`
  - 串接 `topMemoryApps`。
- Modify `GlanceApp/Dropdown/MemorySection.swift`
  - 改吃 `topApps: [AppMemoryUsage]`,用 `AppMemoryList`。
- Modify `GlanceApp/Dropdown/DropdownView.swift`
  - 傳 `s?.topMemoryApps ?? []`。
- Modify 既有測試:`SystemSamplerTests.swift`、`ProcessSamplerCombinedTests.swift`、`MetricsStoreTests.swift`、`MetricHistoryTests.swift`、`MenuBarTextTests.swift`
  - 更新對舊 `topByMemory` / `topMemory` 的引用。

---

### Task 1: AppGrouping 純函式

**Files:**
- Create: `Sources/GlanceCore/Sampling/AppGrouping.swift`
- Test: `Tests/GlanceCoreTests/AppGroupingTests.swift`

- [ ] **Step 1: 寫失敗測試**

Create `Tests/GlanceCoreTests/AppGroupingTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class AppGroupingTests: XCTestCase {
    func testChromeHelperNestedPathGroupsUnderApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "Google Chrome Helper (Renderer)")
        // 取最後一個 .app 元件
        XCTAssertEqual(id.appName, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(id.bundleURL?.path, "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app")
        XCTAssertEqual(id.groupKey, id.bundleURL?.path)
    }

    func testPlainAppGroupsUnderItsBundle() {
        let path = "/Applications/Foo.app/Contents/MacOS/Foo"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "Foo")
        XCTAssertEqual(id.appName, "Foo")
        XCTAssertEqual(id.bundleURL?.path, "/Applications/Foo.app")
        XCTAssertEqual(id.groupKey, "/Applications/Foo.app")
    }

    func testDaemonWithoutAppFallsBackToProcessName() {
        let path = "/usr/sbin/cfprefsd"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "cfprefsd")
        XCTAssertEqual(id.appName, "cfprefsd")
        XCTAssertNil(id.bundleURL)
        XCTAssertEqual(id.groupKey, "cfprefsd")
    }

    func testNilOrEmptyPathFallsBackToProcessName() {
        let idNil = AppGrouping.identity(executablePath: nil, fallbackName: "kernel_task")
        XCTAssertEqual(idNil.appName, "kernel_task")
        XCTAssertNil(idNil.bundleURL)
        XCTAssertEqual(idNil.groupKey, "kernel_task")

        let idEmpty = AppGrouping.identity(executablePath: "", fallbackName: "kernel_task")
        XCTAssertEqual(idEmpty.appName, "kernel_task")
        XCTAssertNil(idEmpty.bundleURL)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter AppGroupingTests`
Expected: 編譯失敗,因為 `AppGrouping` 尚未定義。

- [ ] **Step 3: 實作 AppGrouping**

Create `Sources/GlanceCore/Sampling/AppGrouping.swift`:

```swift
import Foundation

/// 把行程執行檔路徑歸類到所屬 app。純字串運算,不碰檔案系統,易於單元測試。
public enum AppGrouping {
    public struct AppIdentity: Equatable {
        public let groupKey: String
        public let appName: String
        public let bundleURL: URL?
        public init(groupKey: String, appName: String, bundleURL: URL?) {
            self.groupKey = groupKey
            self.appName = appName
            self.bundleURL = bundleURL
        }
    }

    /// 從執行檔路徑找出最後一個 `.app` 包;找不到(或路徑為空/nil)則用 fallbackName。
    public static func identity(executablePath: String?, fallbackName: String) -> AppIdentity {
        guard let path = executablePath, !path.isEmpty else {
            return AppIdentity(groupKey: fallbackName, appName: fallbackName, bundleURL: nil)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
            return AppIdentity(groupKey: fallbackName, appName: fallbackName, bundleURL: nil)
        }
        let appComponent = components[appIndex]
        let appName = String(appComponent.dropLast(".app".count))
        let bundlePath = "/" + components[0...appIndex].joined(separator: "/")
        return AppIdentity(
            groupKey: bundlePath,
            appName: appName.isEmpty ? fallbackName : appName,
            bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true))
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter AppGroupingTests`
Expected: 4 測試全通過。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Sampling/AppGrouping.swift Tests/GlanceCoreTests/AppGroupingTests.swift
git commit -m "feat: [core] 依執行檔路徑把行程歸類到所屬 app"
```

---

### Task 2: RawProcess 執行檔路徑 + AppMemoryUsage 模型 + LibprocSource

**Files:**
- Modify: `Sources/GlanceCore/Model/ProcessUsage.swift`
- Create: `Sources/GlanceCore/Model/AppMemoryUsage.swift`
- Modify: `Sources/GlanceCore/Bridge/LibprocSource.swift`

- [ ] **Step 1: 為 RawProcess 加 executablePath(預設 nil 不破壞既有呼叫)**

Modify `Sources/GlanceCore/Model/ProcessUsage.swift` 的 `RawProcess`:

```swift
/// libproc 取得的單一程式原始資料。cpuTimeSeconds 為累計使用者+系統 CPU 秒數。
public struct RawProcess: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuTimeSeconds: Double
    public let memoryBytes: UInt64
    public let executablePath: String?
    public init(pid: Int32, name: String, cpuTimeSeconds: Double, memoryBytes: UInt64, executablePath: String? = nil) {
        self.pid = pid; self.name = name
        self.cpuTimeSeconds = cpuTimeSeconds; self.memoryBytes = memoryBytes
        self.executablePath = executablePath
    }
}
```

`ProcessUsage` 與 `RawProcessSource` 不變。

- [ ] **Step 2: 新增 AppMemoryUsage 模型**

Create `Sources/GlanceCore/Model/AppMemoryUsage.swift`:

```swift
import Foundation

/// 對外呈現的「按 app 彙總」記憶體用量。memoryBytes 為該 app 所有行程 phys_footprint 加總。
public struct AppMemoryUsage: Equatable, Identifiable {
    public let id: String          // 群組鍵(bundle 路徑或行程名)
    public let appName: String
    public let bundleURL: URL?     // 給 app 層抓圖示;非 app 為 nil
    public let memoryBytes: UInt64
    public let processCount: Int
    public init(id: String, appName: String, bundleURL: URL?, memoryBytes: UInt64, processCount: Int) {
        self.id = id; self.appName = appName; self.bundleURL = bundleURL
        self.memoryBytes = memoryBytes; self.processCount = processCount
    }
}
```

- [ ] **Step 3: LibprocSource 填入 executablePath**

Modify `Sources/GlanceCore/Bridge/LibprocSource.swift` 的 `rawProcess(pid:)` 結尾(取代 `return RawProcess(...)` 那行前後):

```swift
        var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"

        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let executablePath = pathLen > 0 ? String(cString: pathBuf) : nil

        return RawProcess(pid: pid, name: name, cpuTimeSeconds: cpuSeconds, memoryBytes: memory, executablePath: executablePath)
```

- [ ] **Step 4: 編譯確認(套件層)**

Run: `swift build`
Expected: 編譯成功(尚未改 ProcessSampler 回傳型別,既有引用仍可編譯)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Model/ProcessUsage.swift Sources/GlanceCore/Model/AppMemoryUsage.swift Sources/GlanceCore/Bridge/LibprocSource.swift
git commit -m "feat: [core] RawProcess 帶執行檔路徑並新增 AppMemoryUsage 模型"
```

---

### Task 3: ProcessSampler 記憶體彙總 + 全管線改接

**Files:**
- Modify: `Sources/GlanceCore/Sampling/ProcessSampler.swift`
- Modify: `Sources/GlanceCore/SystemSnapshot.swift`
- Modify: `Sources/GlanceCore/Sampling/SystemSampler.swift`
- Create: `Tests/GlanceCoreTests/ProcessSamplerMemoryAppsTests.swift`
- Modify: `Tests/GlanceCoreTests/SystemSamplerTests.swift`
- Modify: `Tests/GlanceCoreTests/ProcessSamplerCombinedTests.swift`
- Modify: `Tests/GlanceCoreTests/MetricsStoreTests.swift`
- Modify: `Tests/GlanceCoreTests/MetricHistoryTests.swift`
- Modify: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1: 寫彙總失敗測試**

Create `Tests/GlanceCoreTests/ProcessSamplerMemoryAppsTests.swift`:

```swift
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

        // Chrome 兩個 helper(同 bundle)合併 5_000 + main 在不同 bundle
        let chromeBundle = apps.first { $0.appName == "Google Chrome Helper" }
        XCTAssertEqual(chromeBundle?.memoryBytes, 5_000)
        XCTAssertEqual(chromeBundle?.processCount, 2)

        // 第一名應為合併後最大者(Chrome Helper 5_000 > Xcode 4_000)
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
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter ProcessSamplerMemoryAppsTests`
Expected: 編譯失敗,因為 `sample()` 尚無 `topMemoryApps`。

- [ ] **Step 3: 改寫 ProcessSampler**

Replace `Sources/GlanceCore/Sampling/ProcessSampler.swift` 全檔為:

```swift
import Foundation

/// 以兩次取樣間各 pid 的 cpu 時間差 ÷ 牆鐘時間差,計算每個程式 CPU 佔比;
/// 記憶體則按所屬 app 彙總(含 helper 子行程)。
public final class ProcessSampler {
    private let source: RawProcessSource
    private let clock: () -> TimeInterval
    private let limit: Int
    private var previous: (byPid: [Int32: Double], time: TimeInterval)?

    public init(source: RawProcessSource,
                clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
                limit: Int = 5) {
        self.source = source
        self.clock = clock
        self.limit = limit
    }

    /// 一次列舉,同時回傳 CPU(單行程)與記憶體(按 app 彙總)排行,避免重複 read()。
    public func sample() -> (topCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
        guard let raws = source.read() else { return ([], []) }
        let t = clock()
        let cpuByPid = Dictionary(uniqueKeysWithValues: raws.map { ($0.pid, $0.cpuTimeSeconds) })
        let prev = previous
        let dt = prev.map { t - $0.time } ?? 0
        previous = (cpuByPid, t)

        let usages: [ProcessUsage] = raws.map { p in
            let fraction: Double
            if let prev, dt > 0, let prevCPU = prev.byPid[p.pid] {
                fraction = max(0, (p.cpuTimeSeconds - prevCPU) / dt)
            } else {
                fraction = 0
            }
            return ProcessUsage(pid: p.pid, name: p.name, cpuFraction: fraction, memoryBytes: p.memoryBytes)
        }
        let topCPU = Array(usages.sorted { $0.cpuFraction > $1.cpuFraction }.prefix(limit))
        let topMemoryApps = Self.aggregateMemory(raws, limit: limit)
        return (topCPU, topMemoryApps)
    }

    public func sampleTopByCPU() -> [ProcessUsage] { sample().topCPU }

    public func sampleTopMemoryApps() -> [AppMemoryUsage] { sample().topMemoryApps }

    /// 按 app 鍵把各行程記憶體加總,由大到小排序取前 limit。
    static func aggregateMemory(_ raws: [RawProcess], limit: Int) -> [AppMemoryUsage] {
        var byKey: [String: (name: String, url: URL?, bytes: UInt64, count: Int)] = [:]
        for p in raws {
            let id = AppGrouping.identity(executablePath: p.executablePath, fallbackName: p.name)
            if var entry = byKey[id.groupKey] {
                entry.bytes += p.memoryBytes
                entry.count += 1
                byKey[id.groupKey] = entry
            } else {
                byKey[id.groupKey] = (id.appName, id.bundleURL, p.memoryBytes, 1)
            }
        }
        let apps = byKey.map { key, v in
            AppMemoryUsage(id: key, appName: v.name, bundleURL: v.url, memoryBytes: v.bytes, processCount: v.count)
        }
        let sorted = apps.sorted {
            $0.memoryBytes == $1.memoryBytes ? $0.appName < $1.appName : $0.memoryBytes > $1.memoryBytes
        }
        return Array(sorted.prefix(limit))
    }
}
```

- [ ] **Step 4: 改 SystemSnapshot 欄位**

Replace `Sources/GlanceCore/SystemSnapshot.swift` 全檔為:

```swift
/// 一次取樣的全部指標聚合。任一指標可能取樣失敗 → nil(故障隔離)。
public struct SystemSnapshot {
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let battery: BatterySnapshot?
    public let sensors: SensorSnapshot?
    public let topByCPU: [ProcessUsage]
    public let topMemoryApps: [AppMemoryUsage]

    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, battery: BatterySnapshot?,
                sensors: SensorSnapshot? = nil,
                topByCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.sensors = sensors
        self.topByCPU = topByCPU; self.topMemoryApps = topMemoryApps
    }
}
```

- [ ] **Step 5: 改 SystemSampler 串接**

Modify `Sources/GlanceCore/Sampling/SystemSampler.swift` 的 `sample()`:

```swift
    public func sample() -> SystemSnapshot {
        let procs = process.sample()
        return SystemSnapshot(
            cpu: cpu.sample(),
            memory: memory.sample(),
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
            sensors: sensor.sample(),
            topByCPU: procs.topCPU,
            topMemoryApps: procs.topMemoryApps)
    }
```

- [ ] **Step 6: 更新既有測試對舊欄位的引用**

在 `Tests/GlanceCoreTests/SystemSamplerTests.swift` 第 41 行:

```swift
        XCTAssertEqual(snap.topMemoryApps.first?.appName, "X")
```

在 `Tests/GlanceCoreTests/ProcessSamplerCombinedTests.swift` 第 27 行:

```swift
        XCTAssertEqual(result.topMemoryApps.first?.appName, "B")
```

在 `Tests/GlanceCoreTests/MetricsStoreTests.swift` 把兩處 `topByMemory: []` 改為 `topMemoryApps: []`(第 9、18 行)。

在 `Tests/GlanceCoreTests/MetricHistoryTests.swift` 把兩處 `topByMemory: []` 改為 `topMemoryApps: []`(第 10、26 行)。

在 `Tests/GlanceCoreTests/MenuBarTextTests.swift` 把 `topByMemory: []` 改為 `topMemoryApps: []`(第 31 行)。

- [ ] **Step 7: 跑全套件測試**

Run: `swift test`
Expected: 全部測試通過(含新 `ProcessSamplerMemoryAppsTests`)。

- [ ] **Step 8: Commit**

```bash
git add Sources/GlanceCore/Sampling/ProcessSampler.swift Sources/GlanceCore/SystemSnapshot.swift Sources/GlanceCore/Sampling/SystemSampler.swift Tests/GlanceCoreTests
git commit -m "feat: [core] 記憶體排行改為按 app 彙總"
```

---

### Task 4: UI 呈現第一名凸顯

**Files:**
- Create: `GlanceApp/Components/AppMemoryList.swift`
- Modify: `GlanceApp/Dropdown/MemorySection.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1: 建立 AppMemoryList 元件**

Create `GlanceApp/Components/AppMemoryList.swift`:

```swift
import AppKit
import SwiftUI
import GlanceCore

/// 按 app 彙總的記憶體排行:第一名以較大列、app 圖示、「最佔用」標籤凸顯。
struct AppMemoryList: View {
    let apps: [AppMemoryUsage]
    let accent: Color

    var body: some View {
        let top = Array(apps.prefix(3))
        let maxVal = max(Double(top.first?.memoryBytes ?? 1), 0.0001)

        VStack(spacing: 5) {
            ForEach(Array(top.enumerated()), id: \.element.id) { index, app in
                row(app, isTop: index == 0, maxVal: maxVal)
            }
        }
    }

    private func row(_ app: AppMemoryUsage, isTop: Bool, maxVal: Double) -> some View {
        let ratio = min(max(Double(app.memoryBytes) / maxVal, 0.0), 1.0)

        return HStack(spacing: 8) {
            icon(for: app)
                .resizable()
                .frame(width: isTop ? 22 : 16, height: isTop ? 22 : 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.appName)
                        .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isTop {
                        Text("最佔用")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accent.opacity(0.18), in: Capsule())
                    }
                }
                if app.processCount > 1 {
                    Text("\(app.processCount) 個行程")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(Formatters.bytes(app.memoryBytes))
                .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isTop ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isTop ? 5 : 3)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(isTop ? 0.14 : 0.07))
                    .frame(width: geo.size.width * CGFloat(ratio))
            }
        }
    }

    private func icon(for app: AppMemoryUsage) -> Image {
        if let url = app.bundleURL {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app.dashed")
    }
}
```

- [ ] **Step 2: 改 MemorySection 使用 AppMemoryList**

Replace `GlanceApp/Dropdown/MemorySection.swift` 全檔為:

```swift
import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let topApps: [AppMemoryUsage]

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        MetricCard(
            title: "記憶體",
            systemImage: "memorychip",
            accent: .blue,
            value: Formatters.percent(usedFraction),
            detail: memoryDetail,
            status: MetricStatus.capacity(fraction: usedFraction)
        ) {
            Sparkline(values: history, maxValue: 1, color: .blue)
                .frame(height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if topApps.isEmpty {
                EmptyMetricLine(text: "暫無高記憶體程式")
            } else {
                AppMemoryList(apps: topApps, accent: .blue)
            }
        }
    }

    private var memoryDetail: String {
        guard let m = snapshot else { return "等待記憶體取樣" }
        return "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes))"
    }
}
```

- [ ] **Step 3: 改 DropdownView 傳 topMemoryApps**

Modify `GlanceApp/Dropdown/DropdownView.swift` 第 17-19 行:

```swift
            MemorySection(snapshot: s?.memory,
                          history: store.history.memory.elements,
                          topApps: s?.topMemoryApps ?? [])
```

- [ ] **Step 4: 產生專案並建置**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: 建置成功。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Components/AppMemoryList.swift GlanceApp/Dropdown/MemorySection.swift GlanceApp/Dropdown/DropdownView.swift Glance.xcodeproj
git commit -m "feat: [app] 記憶體區塊凸顯最佔用 app"
```

---

### Task 5: 最終驗證

**Files:**
- 僅在驗證發現缺陷時修改前述檔案。

- [ ] **Step 1: 跑套件測試**

Run: `swift test`
Expected: 全部通過。

- [ ] **Step 2: 重新產生專案**

Run: `xcodegen generate`
Expected: 無錯誤。

- [ ] **Step 3: 建置 app**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: **BUILD SUCCEEDED**。

- [ ] **Step 4: 啟動 app 實測(記憶體提醒:test/build 綠不代表不閃退)**

Run:

```bash
APP="$(xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')"
open "$APP"
sleep 4
pgrep -x Glance >/dev/null && echo "RUNNING ok" || echo "CRASHED"
```

Expected: `RUNNING ok`。

接著從選單列點開 Glance,人工確認:
- 記憶體區塊第一名是「整個 app 的彙總用量」(例:Chrome 多 helper 合併)。
- 第一名有 app 圖示、加粗、「最佔用」標籤;`N 個行程` 在合併時顯示。
- 數值由大到小排序;非 app 行程(如 daemon)用行程名與泛用圖示。
- CPU 區塊清單維持單行程不變。
- 不閃退。

- [ ] **Step 5: 檢視最終 diff**

Run:

```bash
git diff --stat HEAD~4 HEAD
```

Expected: 變更限縮在 AppGrouping/AppMemoryUsage/ProcessSampler/SystemSnapshot/SystemSampler/LibprocSource、相關測試、AppMemoryList/MemorySection/DropdownView 與 Xcode 專案。

- [ ] **Step 6: 若有修正才提交**

```bash
git add Sources GlanceApp Tests Glance.xcodeproj
git commit -m "fix: [memory] 穩定記憶體 app 彙總驗證路徑"
```

若無修正,不建立空 commit。

## Self-Review

Spec 覆蓋:
- 取得執行檔路徑:Task 2 Step 1、3。
- App 歸類(最後一個 .app / fallback):Task 1。
- AppMemoryUsage 模型:Task 2 Step 2。
- 按 app 加總 + 排序 + 取前 N + processCount:Task 3 Step 3 與測試。
- SystemSnapshot/SystemSampler 改接、移除 per-process topMemory:Task 3 Step 4-5。
- 更新既有測試:Task 3 Step 6。
- UI 第一名凸顯 + 圖示 + 標籤、CPU 不動:Task 4。
- 錯誤處理(path 空/nil fallback、圖示 fallback):Task 1、Task 4 icon()。
- 測試策略全項:Task 1、Task 3、Task 5。

Placeholder 掃描:無 TBD/TODO/模糊步驟,所有程式步驟均含完整程式碼。

型別一致性:`AppGrouping.identity(executablePath:fallbackName:)` → `AppIdentity{groupKey,appName,bundleURL}`;`AppMemoryUsage{id,appName,bundleURL,memoryBytes,processCount}`;`ProcessSampler.sample() -> (topCPU,topMemoryApps)`;`SystemSnapshot.topMemoryApps`;`MemorySection(topApps:)` —— 各 Task 間命名一致。
