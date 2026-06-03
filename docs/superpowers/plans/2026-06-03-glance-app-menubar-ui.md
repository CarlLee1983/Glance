# GlanceApp 選單列 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Plan 1 的 `GlanceCore` 之上,做出常駐 macOS 選單列 app:選單列顯示精簡數字,點開有豐富下拉(歷史曲線 + Top 程式),含設定頁。

**Architecture:** 可測試的反應式邏輯(`SystemSampler`、`MetricsStore`、`MetricHistory`、`MenuBarText`、`percentLoose`)放在 `GlanceCore`,以 `swift test` 涵蓋;SwiftUI views 放在新的 `GlanceApp` Xcode app target(`LSUIElement` agent app),以 `xcodebuild` 建置 + 實機啟動驗證。專案以 XcodeGen 從 `project.yml` 產生 `Glance.xcodeproj`(產物 git 忽略)。

**Tech Stack:** Swift 5.9 / SwiftUI `MenuBarExtra(.window)`、Combine、Canvas 繪圖、XcodeGen、xcodebuild。app 部署目標 macOS 14(用 `MenuBarExtra` 視窗樣式、`SettingsLink`、新版 `onChange`)。

---

## 前置:延續 Plan 1 程式碼審查

本計畫順帶實作 Plan 1 review 的兩個 Minor 建議:
- **單次列舉程式**(原 #3):`ProcessSampler` 加 `sample()` 一次列舉同時產出 CPU/記憶體排行(Task 1)。
- **組裝邏輯上移核心**(原 #7):新增 `SystemSampler`,`glance-cli` 與 `MetricsStore` 共用(Task 2)。

## File Structure

```
Glance/
├─ project.yml                         ← XcodeGen 專案定義(新)
├─ Sources/GlanceCore/
│  ├─ Format/Formatters.swift          (修改:加 percentLoose)
│  ├─ Sampling/ProcessSampler.swift    (修改:加 sample() 單次列舉)
│  ├─ Sampling/SystemSampler.swift     (新:SystemSampling 協定 + 實作)
│  ├─ History/MetricHistory.swift      (新:各指標 RingBuffer<Double>)
│  ├─ MenuBar/MenuBarSegment.swift     (新:選單列欄位列舉 + 組字)
│  └─ Store/MetricsStore.swift         (新:ObservableObject + 計時器)
├─ Sources/glance-cli/main.swift       (修改:改用 SystemSampler)
├─ Tests/GlanceCoreTests/
│  ├─ ProcessSamplerCombinedTests.swift (新)
│  ├─ SystemSamplerTests.swift          (新)
│  ├─ MetricHistoryTests.swift          (新)
│  ├─ MenuBarTextTests.swift            (新)
│  ├─ MetricsStoreTests.swift           (新)
│  └─ FormattersTests.swift             (修改:加 percentLoose 測試)
└─ GlanceApp/                          ← Xcode app target(新)
   ├─ Info.plist
   ├─ GlanceApp.swift                  @main, MenuBarExtra + Settings
   ├─ MenuBar/MenuBarLabel.swift
   ├─ Dropdown/DropdownView.swift
   ├─ Dropdown/CPUSection.swift
   ├─ Dropdown/MemorySection.swift
   ├─ Dropdown/NetworkSection.swift
   ├─ Dropdown/DiskSection.swift
   ├─ Dropdown/BatterySection.swift
   ├─ Components/Sparkline.swift
   ├─ Components/TopProcessList.swift
   └─ Settings/SettingsView.swift
```

**Naming contract**(沿用 Plan 1,後續任務一致):
- 百分比顯示:一般指標用 `Formatters.percent`(clamp 0~100%),程式 CPU 用 `Formatters.percentLoose`(可 >100%)。
- 選單列欄位列舉 `MenuBarSegment`,原始字串持久化於 `@AppStorage("menuBarSegments")`,逗號分隔。
- 更新頻率 `@AppStorage("refreshInterval")`(Double,秒)。

---

## Task 0:Formatters.percentLoose(非 clamp 百分比)

**Files:**
- Modify: `Sources/GlanceCore/Format/Formatters.swift`
- Test: `Tests/GlanceCoreTests/FormattersTests.swift`

- [ ] **Step 1:加失敗測試**

在 `Tests/GlanceCoreTests/FormattersTests.swift` 的 `FormattersTests` class 內,新增一個方法(不要動現有方法):
```swift
    func testPercentLooseAllowsOverHundred() {
        XCTAssertEqual(Formatters.percentLoose(1.5), "150%")
        XCTAssertEqual(Formatters.percentLoose(0.02), "2%")
        XCTAssertEqual(Formatters.percentLoose(-0.1), "0%")
    }
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter FormattersTests`
Expected: FAIL(`type 'Formatters' has no member 'percentLoose'`)

- [ ] **Step 3:實作**

在 `Sources/GlanceCore/Format/Formatters.swift` 的 `Formatters` enum 內,於 `percent(_:)` 之後加入:
```swift
    /// 0... 分數 → 百分比字串,不上限(供多核程式 CPU% 顯示,可 >100%)。
    public static func percentLoose(_ fraction: Double) -> String {
        let v = max(0, fraction)
        return "\(Int((v * 100).rounded()))%"
    }
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter FormattersTests`
Expected: PASS(5 tests)

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/Format/Formatters.swift Tests/GlanceCoreTests/FormattersTests.swift
git commit -m "feat: [glance] add non-clamping percentLoose formatter"
```

---

## Task 1:ProcessSampler 單次列舉 sample()

**Files:**
- Modify: `Sources/GlanceCore/Sampling/ProcessSampler.swift`
- Test: `Tests/GlanceCoreTests/ProcessSamplerCombinedTests.swift`

- [ ] **Step 1:加失敗測試** — `Tests/GlanceCoreTests/ProcessSamplerCombinedTests.swift`
```swift
import XCTest
@testable import GlanceCore

private final class StubProcSource2: RawProcessSource {
    var queue: [[RawProcess]]
    init(_ q: [[RawProcess]]) { queue = q }
    func read() -> [RawProcess]? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class ProcessSamplerCombinedTests: XCTestCase {
    func testSampleReturnsBothRankingsFromOneRead() {
        // A:cpu 高、記憶體低;B:cpu 低、記憶體高
        let first = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.0, memoryBytes: 9_000),
        ]
        let second = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.9, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.1, memoryBytes: 9_000),
        ]
        var times = [0.0, 1.0]
        // 只有 1 組會被消費(combined sample 一次只 read 一次)
        let sampler = ProcessSampler(source: StubProcSource2([first, second]),
                                     clock: { times.removeFirst() }, limit: 5)
        _ = sampler.sample()          // 建立差值基準(消費 first)
        let result = sampler.sample() // 消費 second
        XCTAssertEqual(result.topCPU.first?.name, "A")
        XCTAssertEqual(result.topCPU.first?.cpuFraction ?? -1, 0.9, accuracy: 0.001)
        XCTAssertEqual(result.topMemory.first?.name, "B")
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter ProcessSamplerCombinedTests`
Expected: FAIL(`value of type 'ProcessSampler' has no member 'sample'`)

- [ ] **Step 3:重構 ProcessSampler**

把 `Sources/GlanceCore/Sampling/ProcessSampler.swift` 的 `ProcessSampler` class 內容,改為以下(新增 `sample()` 為核心,`sampleTopByCPU/ByMemory` 改為呼叫它;`init` 與屬性不變):
```swift
    /// 一次列舉,同時回傳 CPU 與記憶體排行,避免重複 read()。
    public func sample() -> (topCPU: [ProcessUsage], topMemory: [ProcessUsage]) {
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
        let topMemory = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (topCPU, topMemory)
    }

    public func sampleTopByCPU() -> [ProcessUsage] { sample().topCPU }

    public func sampleTopByMemory() -> [ProcessUsage] { sample().topMemory }
```
也就是刪掉舊的 `sampleTopByCPU()` / `sampleTopByMemory()` 完整實作,改成上面這三個方法。`import Foundation`、`init`、`source`/`clock`/`limit`/`previous` 屬性保留不動。

- [ ] **Step 4:跑全部 process 測試確認通過**

Run: `swift test --filter ProcessSampler`
Expected: PASS — 既有 `ProcessSamplerTests`(2)與新 `ProcessSamplerCombinedTests`(1)全綠。
註:舊測試 `testComputesCPUFractionFromDelta` 呼叫 `sampleTopByCPU()` 兩次,現會各觸發一次 `sample()`/`read()`,行為與原本相同(stub 佇列有兩組),仍通過。

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/Sampling/ProcessSampler.swift Tests/GlanceCoreTests/ProcessSamplerCombinedTests.swift
git commit -m "refactor: [glance] add single-enumeration ProcessSampler.sample()"
```

---

## Task 2:SystemSampler(組裝層)+ glance-cli 改用

**Files:**
- Create: `Sources/GlanceCore/Sampling/SystemSampler.swift`
- Modify: `Sources/glance-cli/main.swift`
- Test: `Tests/GlanceCoreTests/SystemSamplerTests.swift`

- [ ] **Step 1:加失敗測試** — `Tests/GlanceCoreTests/SystemSamplerTests.swift`
```swift
import XCTest
@testable import GlanceCore

// 以 stub 來源組出真實 sampler,驗證 SystemSampler.sample() 正確委派、聚合。
private struct FixedCPU: CPUTicksSource {
    func read() -> CPUTicks? { CPUTicks(user: 0, system: 0, idle: 100, nice: 0) }
}
private struct FixedMem: MemoryStatsSource {
    func read() -> MemoryStats? {
        MemoryStats(totalBytes: 16, usedBytes: 8, swapUsedBytes: 0, pressure: .normal)
    }
}
private struct FixedNet: NetworkCountersSource {
    func read() -> NetworkCounters? { NetworkCounters(received: 0, sent: 0) }
}
private struct FixedDisk: DiskStatsSource {
    func read() -> DiskStats? { DiskStats(totalBytes: 100, usedBytes: 40) }
}
private struct FixedBattery: BatteryStatsSource {
    func read() -> BatteryStats? { BatteryStats(isPresent: true, chargeFraction: 0.5, isCharging: false) }
}
private struct FixedProc: RawProcessSource {
    func read() -> [RawProcess]? { [RawProcess(pid: 1, name: "X", cpuTimeSeconds: 0, memoryBytes: 10)] }
}

final class SystemSamplerTests: XCTestCase {
    func testSampleAggregatesAllMetrics() {
        let sampler = SystemSampler(
            cpu: CPUSampler(source: FixedCPU()),
            memory: MemorySampler(source: FixedMem()),
            network: NetworkSampler(source: FixedNet(), clock: { 0 }),
            disk: DiskSampler(source: FixedDisk()),
            battery: BatterySampler(source: FixedBattery()),
            process: ProcessSampler(source: FixedProc(), clock: { 0 }, limit: 5))
        let snap = sampler.sample()
        XCTAssertNotNil(snap.memory)
        XCTAssertEqual(snap.disk?.usedBytes, 40)
        XCTAssertEqual(snap.battery?.chargeFraction, 0.5)
        XCTAssertEqual(snap.topByMemory.first?.name, "X")
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter SystemSamplerTests`
Expected: FAIL(`cannot find 'SystemSampler' in scope`)

- [ ] **Step 3:實作 SystemSampler** — `Sources/GlanceCore/Sampling/SystemSampler.swift`
```swift
/// 一次取樣全部指標的抽象(可注入測試替身給 MetricsStore)。
public protocol SystemSampling {
    func sample() -> SystemSnapshot
}

/// 組裝所有 Sampler,產出一次 SystemSnapshot。程式列舉只做一次(CPU/記憶體共用)。
public final class SystemSampler: SystemSampling {
    private let cpu: CPUSampler
    private let memory: MemorySampler
    private let network: NetworkSampler
    private let disk: DiskSampler
    private let battery: BatterySampler
    private let process: ProcessSampler

    public init(cpu: CPUSampler, memory: MemorySampler, network: NetworkSampler,
                disk: DiskSampler, battery: BatterySampler, process: ProcessSampler) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.process = process
    }

    /// 以真實系統來源建立。
    public convenience init() {
        self.init(
            cpu: CPUSampler(source: MachCPUSource()),
            memory: MemorySampler(source: MachMemorySource()),
            network: NetworkSampler(source: InterfaceCountersSource()),
            disk: DiskSampler(source: StatfsDiskSource()),
            battery: BatterySampler(source: IOKitBatterySource()),
            process: ProcessSampler(source: LibprocSource(), limit: 5))
    }

    public func sample() -> SystemSnapshot {
        let procs = process.sample()
        return SystemSnapshot(
            cpu: cpu.sample(),
            memory: memory.sample(),
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
            topByCPU: procs.topCPU,
            topByMemory: procs.topMemory)
    }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter SystemSamplerTests`
Expected: PASS(1 test)

- [ ] **Step 5:glance-cli 改用 SystemSampler(DRY)**

把 `Sources/glance-cli/main.swift` 中 從 `let cpu = ...` 到 `let s = sampleAll()` 這段(各別建立 sampler + `sampleAll()` 函式 + 兩次取樣)替換為:
```swift
let sampler = SystemSampler()
_ = sampler.sample()            // 第一筆:建立差值基準
Thread.sleep(forTimeInterval: 1)
let s = sampler.sample()
```
其餘印出區塊(`func line` 與 `print` 們)保持不變。注意 `s.cpu` / `s.memory` 等欄位名稱不變,印出區塊不需改。

- [ ] **Step 6:跑全測試 + CLI smoke**

Run: `swift test`
Expected: PASS(全綠)
Run: `swift run glance-cli`
Expected: 與 Plan 1 相同,印出合理的 CPU/記憶體/網路/磁碟/電池 + Top CPU。

- [ ] **Step 7:Commit**

```bash
git add Sources/GlanceCore/Sampling/SystemSampler.swift Sources/glance-cli/main.swift Tests/GlanceCoreTests/SystemSamplerTests.swift
git commit -m "feat: [glance] add SystemSampler; glance-cli reuses it"
```

---

## Task 3:MetricHistory(各指標歷史環形緩衝)

**Files:**
- Create: `Sources/GlanceCore/History/MetricHistory.swift`
- Test: `Tests/GlanceCoreTests/MetricHistoryTests.swift`

- [ ] **Step 1:加失敗測試** — `Tests/GlanceCoreTests/MetricHistoryTests.swift`
```swift
import XCTest
@testable import GlanceCore

final class MetricHistoryTests: XCTestCase {
    private func snapshot(cpu: Double, mem: Double, down: Double, up: Double) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpu, user: cpu, system: 0, idle: 1 - cpu),
            memory: MemorySnapshot(usedBytes: UInt64(mem * 100), totalBytes: 100, swapUsedBytes: 0, pressure: .normal),
            network: NetworkSnapshot(downBytesPerSec: down, upBytesPerSec: up, totalDownBytes: 0, totalUpBytes: 0),
            disk: nil, battery: nil, topByCPU: [], topByMemory: [])
    }

    func testRecordAppendsPerMetric() {
        var h = MetricHistory(capacity: 5)
        h.record(snapshot(cpu: 0.2, mem: 0.6, down: 1000, up: 50))
        h.record(snapshot(cpu: 0.3, mem: 0.61, down: 2000, up: 60))
        XCTAssertEqual(h.cpu.elements, [0.2, 0.3])
        XCTAssertEqual(h.memory.elements, [0.6, 0.61], accuracy: 0.0001)
        XCTAssertEqual(h.netDown.elements, [1000, 2000])
        XCTAssertEqual(h.netUp.elements, [50, 60])
    }

    func testMissingMetricRecordsZero() {
        var h = MetricHistory(capacity: 5)
        let empty = SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topByMemory: [])
        h.record(empty)
        XCTAssertEqual(h.cpu.elements, [0])
        XCTAssertEqual(h.netDown.elements, [0])
    }

    func testRespectsCapacity() {
        var h = MetricHistory(capacity: 2)
        h.record(snapshot(cpu: 0.1, mem: 0, down: 0, up: 0))
        h.record(snapshot(cpu: 0.2, mem: 0, down: 0, up: 0))
        h.record(snapshot(cpu: 0.3, mem: 0, down: 0, up: 0))
        XCTAssertEqual(h.cpu.elements, [0.2, 0.3])
    }
}
```
註:`XCTAssertEqual([Double], [Double], accuracy:)` 為 XCTest 內建的陣列重載。

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter MetricHistoryTests`
Expected: FAIL(`cannot find 'MetricHistory' in scope`)

- [ ] **Step 3:實作** — `Sources/GlanceCore/History/MetricHistory.swift`
```swift
/// 各指標各一條 RingBuffer<Double>,供下拉的歷史曲線使用。缺值記 0 以維持曲線連續。
public struct MetricHistory {
    public private(set) var cpu: RingBuffer<Double>
    public private(set) var memory: RingBuffer<Double>
    public private(set) var netDown: RingBuffer<Double>
    public private(set) var netUp: RingBuffer<Double>

    public init(capacity: Int = 90) {
        cpu = RingBuffer(capacity: capacity)
        memory = RingBuffer(capacity: capacity)
        netDown = RingBuffer(capacity: capacity)
        netUp = RingBuffer(capacity: capacity)
    }

    public mutating func record(_ snapshot: SystemSnapshot) {
        cpu.append(snapshot.cpu?.totalUsage ?? 0)
        memory.append(snapshot.memory?.usedFraction ?? 0)
        netDown.append(snapshot.network?.downBytesPerSec ?? 0)
        netUp.append(snapshot.network?.upBytesPerSec ?? 0)
    }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter MetricHistoryTests`
Expected: PASS(3 tests)

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/History/MetricHistory.swift Tests/GlanceCoreTests/MetricHistoryTests.swift
git commit -m "feat: [glance] add MetricHistory ring buffers"
```

---

## Task 4:MenuBarSegment 與選單列組字

**Files:**
- Create: `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
- Test: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1:加失敗測試** — `Tests/GlanceCoreTests/MenuBarTextTests.swift`
```swift
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
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter MenuBarTextTests`
Expected: FAIL(`cannot find 'MenuBarText' / 'MenuBarSegment' in scope`)

- [ ] **Step 3:實作** — `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
```swift
/// 選單列上可顯示的欄位。allCases 的順序即為畫面顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network
}

/// 把 snapshot 依選定欄位組成選單列精簡字串,例如 "23% · 61% · ↓2.1M"。
public enum MenuBarText {
    public static func compose(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> String {
        guard let snapshot else { return "—" }
        var parts: [String] = []
        for seg in segments {
            switch seg {
            case .cpu:
                if let c = snapshot.cpu { parts.append(Formatters.percent(c.totalUsage)) }
            case .memory:
                if let m = snapshot.memory { parts.append(Formatters.percent(m.usedFraction)) }
            case .network:
                if let n = snapshot.network { parts.append("↓\(Formatters.rateCompact(n.downBytesPerSec))") }
            }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter MenuBarTextTests`
Expected: PASS(4 tests)

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift
git commit -m "feat: [glance] add MenuBarSegment and menu-bar text composer"
```

---

## Task 5:MetricsStore(ObservableObject + 計時器)

**Files:**
- Create: `Sources/GlanceCore/Store/MetricsStore.swift`
- Test: `Tests/GlanceCoreTests/MetricsStoreTests.swift`

- [ ] **Step 1:加失敗測試** — `Tests/GlanceCoreTests/MetricsStoreTests.swift`
```swift
import XCTest
@testable import GlanceCore

private final class StubSystemSampler: SystemSampling {
    var queue: [SystemSnapshot]
    init(_ q: [SystemSnapshot]) { queue = q }
    func sample() -> SystemSnapshot {
        queue.isEmpty
            ? SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topByMemory: [])
            : queue.removeFirst()
    }
}

final class MetricsStoreTests: XCTestCase {
    private func snap(cpu: Double) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpu, user: cpu, system: 0, idle: 1 - cpu),
            memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topByMemory: [])
    }

    func testTickUpdatesSnapshotAndHistory() {
        let store = MetricsStore(sampler: StubSystemSampler([snap(cpu: 0.1), snap(cpu: 0.2)]), historyCapacity: 90)
        store.tick()
        XCTAssertEqual(store.snapshot?.cpu?.totalUsage, 0.1)
        XCTAssertEqual(store.history.cpu.elements, [0.1])
        store.tick()
        XCTAssertEqual(store.snapshot?.cpu?.totalUsage, 0.2)
        XCTAssertEqual(store.history.cpu.elements, [0.1, 0.2])
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter MetricsStoreTests`
Expected: FAIL(`cannot find 'MetricsStore' in scope`)

- [ ] **Step 3:實作** — `Sources/GlanceCore/Store/MetricsStore.swift`
```swift
import Foundation
import Combine

/// 反應式狀態中樞:計時器定期取樣,發佈最新 snapshot 與歷史。供 SwiftUI 觀察。
public final class MetricsStore: ObservableObject {
    @Published public private(set) var snapshot: SystemSnapshot?
    @Published public private(set) var history: MetricHistory

    private let sampler: SystemSampling
    private var timer: DispatchSourceTimer?

    public init(sampler: SystemSampling, historyCapacity: Int = 90) {
        self.sampler = sampler
        self.history = MetricHistory(capacity: historyCapacity)
    }

    /// 取樣一次並更新狀態(同步;測試可直接呼叫)。
    public func tick() {
        apply(sampler.sample())
    }

    func apply(_ snap: SystemSnapshot) {
        snapshot = snap
        history.record(snap)
    }

    /// 啟動定期取樣。取樣在背景佇列、發佈切回主執行緒。重複呼叫會先停舊計時器。
    public func start(interval: TimeInterval) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let snap = self.sampler.sample()
            DispatchQueue.main.async { self.apply(snap) }
        }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter MetricsStoreTests`
Expected: PASS(1 test)

- [ ] **Step 5:跑全測試**

Run: `swift test`
Expected: PASS(全綠;此時核心邏輯全數完成)

- [ ] **Step 6:Commit**

```bash
git add Sources/GlanceCore/Store/MetricsStore.swift Tests/GlanceCoreTests/MetricsStoreTests.swift
git commit -m "feat: [glance] add MetricsStore observable with timer"
```

---

## Task 6:XcodeGen 專案 + 最小可啟動選單列 app

**Files:**
- Create: `project.yml`
- Create: `GlanceApp/Info.plist`
- Create: `GlanceApp/GlanceApp.swift`
- Modify: `.gitignore`

> 本任務只求「Xcode app target 能 build 並在選單列出現一個項目」,證明 XcodeGen + 本地套件 + MenuBarExtra + agent app 的管線可行。真實 views 在後續任務加入並於 Task 10 接上。

- [ ] **Step 1:確認 xcodegen 可用**

Run: `which xcodegen || brew install xcodegen`
Expected: 印出 xcodegen 路徑(若未安裝則經 brew 安裝後再得到路徑)。

- [ ] **Step 2:建立 `project.yml`**
```yaml
name: Glance
options:
  bundleIdPrefix: com.carl.glance
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  GlanceCore:
    path: .
targets:
  Glance:
    type: application
    platform: macOS
    sources:
      - GlanceApp
    dependencies:
      - package: GlanceCore
        product: GlanceCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.carl.glance
        GENERATE_INFOPLIST_FILE: NO
        INFOPLIST_FILE: GlanceApp/Info.plist
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
        CODE_SIGNING_ALLOWED: "NO"
        SWIFT_VERSION: "5.0"
```

- [ ] **Step 3:建立 `GlanceApp/Info.plist`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>Glance</string>
    <key>CFBundleIdentifier</key>
    <string>com.carl.glance</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 4:建立最小 `GlanceApp/GlanceApp.swift`**
```swift
import SwiftUI

@main
struct GlanceApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Glance v0.1")
                .padding(12)
        } label: {
            Text("📊")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5:忽略 XcodeGen 產物**

在 `.gitignore` 末尾加一行:
```
Glance.xcodeproj/
```

- [ ] **Step 6:產生專案並建置**

Run:
```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' -configuration Debug build
```
Expected: 結尾出現 `** BUILD SUCCEEDED **`。

- [ ] **Step 7:Commit**

```bash
git add project.yml GlanceApp/Info.plist GlanceApp/GlanceApp.swift .gitignore
git commit -m "feat: [glance] scaffold GlanceApp menu bar target via XcodeGen"
```

---

## Task 7:Sparkline 曲線元件

**Files:**
- Create: `GlanceApp/Components/Sparkline.swift`

> SwiftUI 純視圖,以 `xcodebuild` 編譯驗證。

- [ ] **Step 1:實作** — `GlanceApp/Components/Sparkline.swift`
```swift
import SwiftUI

/// 由一串數值畫出迷你折線 + 區域填色。maxValue 為 nil 時以資料最大值自動縮放。
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.15))

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, lineWidth: 1.5)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = min(max(v, 0), maxV)
            let y = size.height - CGFloat(clamped / maxV) * size.height
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }
}
```

- [ ] **Step 2:建置驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`
(註:Sparkline 尚未被引用,只需確認可編譯。)

- [ ] **Step 3:Commit**

```bash
git add GlanceApp/Components/Sparkline.swift
git commit -m "feat: [glance] add Sparkline canvas component"
```

---

## Task 8:TopProcessList 與各指標 Section

**Files:**
- Create: `GlanceApp/Components/TopProcessList.swift`
- Create: `GlanceApp/Dropdown/CPUSection.swift`
- Create: `GlanceApp/Dropdown/MemorySection.swift`
- Create: `GlanceApp/Dropdown/NetworkSection.swift`
- Create: `GlanceApp/Dropdown/DiskSection.swift`
- Create: `GlanceApp/Dropdown/BatterySection.swift`

- [ ] **Step 1:TopProcessList** — `GlanceApp/Components/TopProcessList.swift`
```swift
import SwiftUI
import GlanceCore

/// 列出前幾名程式:名稱 + 右側數值(數值字串由呼叫端決定,CPU 用 percentLoose、記憶體用 bytes)。
struct TopProcessList: View {
    let processes: [ProcessUsage]
    let valueText: (ProcessUsage) -> String

    var body: some View {
        VStack(spacing: 2) {
            ForEach(processes.prefix(3), id: \.pid) { p in
                HStack {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text(valueText(p)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
```

- [ ] **Step 2:CPUSection** — `GlanceApp/Dropdown/CPUSection.swift`
```swift
import SwiftUI
import GlanceCore

struct CPUSection: View {
    let snapshot: CPUSnapshot?
    let history: [Double]
    let topProcesses: [ProcessUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU").font(.headline)
                Spacer()
                Text(Formatters.percent(snapshot?.totalUsage ?? 0)).monospacedDigit()
            }
            Sparkline(values: history, maxValue: 1, color: .green)
                .frame(height: 40)
            TopProcessList(processes: topProcesses) { Formatters.percentLoose($0.cpuFraction) }
        }
    }
}
```

- [ ] **Step 3:MemorySection** — `GlanceApp/Dropdown/MemorySection.swift`
```swift
import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let topProcesses: [ProcessUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("記憶體").font(.headline)
                Spacer()
                if let m = snapshot {
                    Text("\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes))")
                        .monospacedDigit().font(.callout)
                }
            }
            Sparkline(values: history, maxValue: 1, color: .blue)
                .frame(height: 40)
            TopProcessList(processes: topProcesses) { Formatters.bytes($0.memoryBytes) }
        }
    }
}
```

- [ ] **Step 4:NetworkSection** — `GlanceApp/Dropdown/NetworkSection.swift`
```swift
import SwiftUI
import GlanceCore

struct NetworkSection: View {
    let snapshot: NetworkSnapshot?
    let downHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("網路").font(.headline)
                Spacer()
                if let n = snapshot {
                    Text("↓\(Formatters.rateCompact(n.downBytesPerSec))  ↑\(Formatters.rateCompact(n.upBytesPerSec))")
                        .monospacedDigit().font(.callout)
                }
            }
            Sparkline(values: downHistory, maxValue: nil, color: .orange)
                .frame(height: 40)
        }
    }
}
```

- [ ] **Step 5:DiskSection** — `GlanceApp/Dropdown/DiskSection.swift`
```swift
import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("磁碟").font(.headline)
                Spacer()
                if let d = snapshot {
                    Text("\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes))")
                        .monospacedDigit().font(.callout)
                }
            }
            ProgressView(value: snapshot?.usedFraction ?? 0)
                .tint(.yellow)
        }
    }
}
```

- [ ] **Step 6:BatterySection** — `GlanceApp/Dropdown/BatterySection.swift`
```swift
import SwiftUI
import GlanceCore

struct BatterySection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack {
            Text("電池").font(.headline)
            Spacer()
            Text("\(Formatters.percent(snapshot.chargeFraction))\(snapshot.isCharging ? " ⚡" : "")")
                .monospacedDigit()
        }
    }
}
```

- [ ] **Step 7:建置驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8:Commit**

```bash
git add GlanceApp/Components/TopProcessList.swift GlanceApp/Dropdown
git commit -m "feat: [glance] add per-metric dropdown sections and process list"
```

---

## Task 9:DropdownView 組合

**Files:**
- Create: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1:實作** — `GlanceApp/Dropdown/DropdownView.swift`
```swift
import SwiftUI
import GlanceCore

/// 點開選單列後的詳情視圖:各指標區塊 + 設定 / 結束。
struct DropdownView: View {
    @ObservedObject var store: MetricsStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 14) {
            CPUSection(snapshot: s?.cpu,
                       history: store.history.cpu.elements,
                       topProcesses: s?.topByCPU ?? [])
            Divider()
            MemorySection(snapshot: s?.memory,
                          history: store.history.memory.elements,
                          topProcesses: s?.topByMemory ?? [])
            Divider()
            NetworkSection(snapshot: s?.network,
                           downHistory: store.history.netDown.elements)
            Divider()
            DiskSection(snapshot: s?.disk)
            if let b = s?.battery, b.isPresent {
                Divider()
                BatterySection(snapshot: b)
            }
            Divider()
            HStack {
                SettingsLink { Text("設定…") }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
    }
}
```

- [ ] **Step 2:建置驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`
(註:DropdownView 尚未被 GlanceApp 引用,只確認可編譯;`SettingsLink` 需 macOS 14,已符合部署目標。)

- [ ] **Step 3:Commit**

```bash
git add GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [glance] assemble DropdownView"
```

---

## Task 10:MenuBarLabel 與接上 MetricsStore

**Files:**
- Create: `GlanceApp/MenuBar/MenuBarLabel.swift`
- Modify: `GlanceApp/GlanceApp.swift`

- [ ] **Step 1:MenuBarLabel** — `GlanceApp/MenuBar/MenuBarLabel.swift`
```swift
import SwiftUI
import GlanceCore

/// 選單列常駐標籤:精簡數字。首次出現時啟動取樣計時器,頻率變更時重啟。
struct MenuBarLabel: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"

    private var segments: [MenuBarSegment] {
        segmentsRaw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
    }

    var body: some View {
        Text(MenuBarText.compose(snapshot: store.snapshot, segments: segments))
            .monospacedDigit()
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }
}
```

- [ ] **Step 2:改寫 `GlanceApp/GlanceApp.swift` 接上 store 與真實 views**
```swift
import SwiftUI
import GlanceCore

@main
struct GlanceApp: App {
    @StateObject private var store = MetricsStore(sampler: SystemSampler())

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3:建置 + 實機啟動 smoke**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

找出產物並啟動:
```bash
APP=$(xcodebuild -project Glance.xcodeproj -scheme Glance -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{d=$3} / FULL_PRODUCT_NAME =/{n=$3} END{print d"/"n}')
open "$APP"
```
Expected(實機目視):選單列右側出現精簡數字(初次約為 `0% · …`,約 1–2 秒後跳成真實值如 `23% · 61% · ↓2.1M`)。點開出現 CPU/記憶體/網路/磁碟(及電池)區塊,CPU/記憶體有曲線、列出 Top 程式。「結束」可關閉。
若選單列無項目或閃退,回報 BLOCKED 並附 Console 錯誤;先別亂改。

- [ ] **Step 4:Commit**

```bash
git add GlanceApp/MenuBar/MenuBarLabel.swift GlanceApp/GlanceApp.swift
git commit -m "feat: [glance] wire MenuBarLabel and dropdown to MetricsStore"
```

---

## Task 11:設定頁

**Files:**
- Create: `GlanceApp/Settings/SettingsView.swift`
- Modify: `GlanceApp/GlanceApp.swift`

- [ ] **Step 1:SettingsView** — `GlanceApp/Settings/SettingsView.swift`
```swift
import SwiftUI
import GlanceCore

/// 設定:更新頻率(1~5 秒)與選單列要顯示哪幾格。皆以 @AppStorage 持久化。
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"

    private var selected: Set<String> {
        Set(segmentsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        Form {
            Section("更新頻率") {
                Slider(value: $refreshInterval, in: 1...5, step: 1)
                Text("每 \(Int(refreshInterval)) 秒更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列顯示") {
                ForEach(MenuBarSegment.allCases, id: \.self) { seg in
                    Toggle(label(seg), isOn: Binding(
                        get: { selected.contains(seg.rawValue) },
                        set: { isOn in
                            var set = selected
                            if isOn { set.insert(seg.rawValue) } else { set.remove(seg.rawValue) }
                            // 以 allCases 的順序寫回,維持顯示順序一致
                            segmentsRaw = MenuBarSegment.allCases
                                .filter { set.contains($0.rawValue) }
                                .map(\.rawValue)
                                .joined(separator: ",")
                        }))
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func label(_ s: MenuBarSegment) -> String {
        switch s {
        case .cpu: return "CPU"
        case .memory: return "記憶體"
        case .network: return "網路"
        }
    }
}
```

- [ ] **Step 2:在 `GlanceApp/GlanceApp.swift` 加入 Settings 場景**

把 `var body: some Scene { ... }` 改為(在 MenuBarExtra 之後加一個 `Settings` 場景):
```swift
    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
```

- [ ] **Step 3:建置 + 實機驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

重新啟動 app(先關掉舊的:`pkill -x Glance` 後再 `open "$APP"`),點下拉的「設定…」:
- 調整更新頻率,觀察選單列數字更新節奏改變。
- 取消勾選「網路」,選單列字串應變為僅 `CPU · 記憶體` 兩格。
若設定不生效,回報 DONE_WITH_CONCERNS 並描述觀察。

- [ ] **Step 4:Commit**

```bash
git add GlanceApp/Settings/SettingsView.swift GlanceApp/GlanceApp.swift
git commit -m "feat: [glance] add settings (refresh rate, menu-bar segments)"
```

---

## Task 12:收尾驗證與 README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1:全面驗證**

Run: `swift test`
Expected: 全綠(核心邏輯;預估約 30+ 測試)。
Run: `xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2:更新 README** — 在 `README.md` 的「使用」段落後新增「選單列 App」段落:
```markdown
## 選單列 App(GlanceApp)

需先安裝 XcodeGen(`brew install xcodegen`),再:

```bash
xcodegen generate          # 由 project.yml 產生 Glance.xcodeproj
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池 區塊(CPU/記憶體含歷史曲線與 Top 程式)。下拉內可開「設定…」調整更新頻率與選單列顯示欄位。
```

- [ ] **Step 3:Commit**

```bash
git add README.md
git commit -m "docs: [glance] document GlanceApp menu bar usage"
```

---

## Self-Review Notes

- **Spec 覆蓋**:選單列精簡字串(B 風格、無時鐘)= `MenuBarText` + `MenuBarLabel`(Task 4/10);豐富下拉(曲線 + Top 程式)= Sparkline + Sections + TopProcessList(Task 7/8/9);CPU/記憶體/網路/磁碟/電池五指標皆有 Section;`MetricsStore`(計時器 + ObservableObject)= Task 5;設定(頻率 + 顯示欄位)= Task 11;agent app(`LSUIElement`)= Task 6 Info.plist。溫度/風扇、登入啟動、公證依 spec 排除。
- **延續 Plan 1 review**:單次列舉(Task 1)、SystemSampler 上移核心並讓 CLI 共用(Task 2)、程式 CPU% 用非 clamp 的 percentLoose(Task 0/8)。
- **型別一致**:`MenuBarSegment` rawValue(cpu/memory/network)同時用於 `@AppStorage("menuBarSegments")` 持久化、`MenuBarText.compose`、`SettingsView`;`MetricsStore` 對 `SystemSampling` 協定相依,測試注入 stub;`store.history.<metric>.elements` 取陣列供 Sparkline。`Formatters.percent`(clamp)用於一般指標、`percentLoose` 用於程式 CPU。
- **可測試 vs 視圖邊界**:所有可單元測試的邏輯在 GlanceCore(swift test);GlanceApp 僅 SwiftUI views,以 xcodebuild + 實機啟動涵蓋。
- **無 placeholder**:每個 code step 均為完整可編譯/可貼上的內容。
- **部署目標**:app 設 macOS 14(`MenuBarExtra(.window)`、`SettingsLink`、雙參數 `onChange`);核心套件仍支援 macOS 13。已於 Tech Stack 與 Info.plist 一致標註。
