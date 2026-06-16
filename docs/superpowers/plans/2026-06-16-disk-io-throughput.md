# 磁碟即時讀寫量(Disk I/O Throughput)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 磁碟卡片補上即時讀/寫速率(↑寫、↓讀,bytes/sec),加總全部實體磁碟。

**Architecture:** 完全鏡像現有「網路速率」差值取樣模式——注入 raw source + clock,兩次累計位元組差值 ÷ 經過時間。新增獨立 `DiskIOSnapshot` / `DiskIOSampler` / `IOBlockStorageIOSource`(公開 IOKit),`SystemSnapshot` 加 `diskIO` 欄,磁碟卡片與 CLI 各加一行顯示。不動既有型別語意、不加歷史/sparkline/選單列欄位。

**Tech Stack:** Swift 5.9、SwiftPM、SwiftUI、IOKit(`IOBlockStorageDriver` Statistics)。

**對應 spec:** `docs/superpowers/specs/2026-06-16-disk-io-throughput-design.md`

**全建置指令:** `swift build`　**全測試指令:** `swift test`

---

## 檔案總覽

| 動作 | 路徑 | 職責 |
| --- | --- | --- |
| Create | `Sources/GlanceCore/Model/DiskIOSnapshot.swift` | `DiskIOCounters` / `DiskIOSnapshot` / `DiskIOStatsSource` protocol |
| Create | `Sources/GlanceCore/Sampling/DiskIOSampler.swift` | 差值 ÷ 時間算速率(注入 source + clock) |
| Create | `Sources/GlanceCore/Bridge/IOBlockStorageIOSource.swift` | 公開 IOKit 讀全部實體磁碟 Statistics 加總 |
| Create | `Tests/GlanceCoreTests/DiskIOSamplerTests.swift` | Sampler 單元測試 |
| Modify | `Sources/GlanceCore/SystemSnapshot.swift` | 新增 `diskIO: DiskIOSnapshot?` 欄 |
| Modify | `Sources/GlanceCore/Sampling/SystemSampler.swift` | 接 `DiskIOSampler`(預設參數、故障隔離) |
| Modify | `Sources/glance-cli/main.swift` | 印「磁碟 I/O」行 |
| Modify | `GlanceApp/Dropdown/DiskSection.swift` | 加 `io` 參數與讀/寫速率行 |
| Modify | `GlanceApp/Dropdown/DropdownView.swift` | 傳 `io: s?.diskIO` |
| Modify | `README.md` | 架構表/說明補一行 |

---

### Task 1: 資料模型型別(DiskIOSnapshot)

**Files:**
- Create: `Sources/GlanceCore/Model/DiskIOSnapshot.swift`

> 純資料型別,比照 `Model/NetworkSnapshot.swift`(累計計數 struct + 速率 snapshot struct + source protocol)。無單元測試(plain data),以建置確認可編譯。

- [ ] **Step 1: 建立型別檔**

Create `Sources/GlanceCore/Model/DiskIOSnapshot.swift`:

```swift
/// 全部實體磁碟自開機起的累計讀/寫位元組數。
public struct DiskIOCounters: Equatable {
    public let readBytes: UInt64
    public let writeBytes: UInt64
    public init(readBytes: UInt64, writeBytes: UInt64) {
        self.readBytes = readBytes; self.writeBytes = writeBytes
    }
}

public struct DiskIOSnapshot: Equatable {
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public init(readBytesPerSec: Double, writeBytesPerSec: Double) {
        self.readBytesPerSec = readBytesPerSec; self.writeBytesPerSec = writeBytesPerSec
    }
}

public protocol DiskIOStatsSource {
    func read() -> DiskIOCounters?
}
```

- [ ] **Step 2: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/GlanceCore/Model/DiskIOSnapshot.swift
git commit -m "feat: [core] 新增磁碟 I/O 計數/快照型別與 source protocol"
```

---

### Task 2: DiskIOSampler(差值取樣,TDD)

**Files:**
- Create: `Tests/GlanceCoreTests/DiskIOSamplerTests.swift`
- Create: `Sources/GlanceCore/Sampling/DiskIOSampler.swift`

> 比照 `NetworkSampler` / `NetworkSamplerTests`:首次取樣回速率 0、第二次回差值 ÷ dt、`dt ≤ 0` 回 0、counter 環繞用 `&-`。

- [ ] **Step 1: 寫失敗測試**

Create `Tests/GlanceCoreTests/DiskIOSamplerTests.swift`:

```swift
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
        // +4_194_304 讀 / 2 秒 = 2_097_152 B/s;+1_048_576 寫 / 2 秒 = 524_288 B/s
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
        let sampler = DiskIOSampler(source: src, clock: { 5 }) // dt == 0
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.readBytesPerSec, 0)
        XCTAssertEqual(snap?.writeBytesPerSec, 0)
    }

    func testCounterWrapDoesNotCrash() {
        // now < prev:以 &- 環繞,不應崩潰
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskIOSamplerTests`
Expected: 編譯失敗 / FAIL,因 `DiskIOSampler` 尚未定義。

- [ ] **Step 3: 實作 DiskIOSampler**

Create `Sources/GlanceCore/Sampling/DiskIOSampler.swift`:

```swift
import Foundation

/// 以兩次累計位元組差值 ÷ 經過時間計算讀/寫速率。clock 可注入以便測試。
public final class DiskIOSampler {
    private let source: DiskIOStatsSource
    private let clock: () -> TimeInterval
    private var previous: (counters: DiskIOCounters, time: TimeInterval)?

    public init(source: DiskIOStatsSource, clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.source = source
        self.clock = clock
    }

    public func sample() -> DiskIOSnapshot? {
        guard let now = source.read() else { return nil }
        let t = clock()
        defer { previous = (now, t) }
        guard let prev = previous else {
            return DiskIOSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0)
        }
        let dt = t - prev.time
        guard dt > 0 else {
            return DiskIOSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0)
        }
        let read = Double(now.readBytes &- prev.counters.readBytes) / dt
        let write = Double(now.writeBytes &- prev.counters.writeBytes) / dt
        return DiskIOSnapshot(readBytesPerSec: read, writeBytesPerSec: write)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskIOSamplerTests`
Expected: PASS(5 個測試)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Sampling/DiskIOSampler.swift Tests/GlanceCoreTests/DiskIOSamplerTests.swift
git commit -m "feat: [core] 新增 DiskIOSampler 差值取樣讀/寫速率(含單元測試)"
```

---

### Task 3: IOKit Bridge 來源(IOBlockStorageIOSource)

**Files:**
- Create: `Sources/GlanceCore/Bridge/IOBlockStorageIOSource.swift`

> 公開 IOKit:列舉所有 `IOBlockStorageDriver`(實體磁碟層,內建/外接/磁碟映像皆涵蓋),讀各自 `Statistics` 字典的 `Bytes (Read)`/`Bytes (Write)` 加總。碰真實系統不單測,改由 Task 5 的 `glance-cli` 實機驗證(同 `InterfaceCountersSource` 慣例)。任一步失敗回 nil;個別磁碟缺鍵則略過,不崩。

- [ ] **Step 1: 建立來源檔**

Create `Sources/GlanceCore/Bridge/IOBlockStorageIOSource.swift`:

```swift
import Foundation
import IOKit

/// 列舉所有實體磁碟(IOBlockStorageDriver),加總累計讀/寫位元組。
public struct IOBlockStorageIOSource: DiskIOStatsSource {
    public init() {}

    public func read() -> DiskIOCounters? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var found = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = statistics(of: service) {
                if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totalRead += r; found = true
                }
                if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totalWrite += w; found = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return found ? DiskIOCounters(readBytes: totalRead, writeBytes: totalWrite) : nil
    }

    /// 取出某 driver 的 Statistics 子字典(找不到回 nil)。
    private func statistics(of service: io_object_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict["Statistics"] as? [String: Any]
    }
}
```

- [ ] **Step 2: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/GlanceCore/Bridge/IOBlockStorageIOSource.swift
git commit -m "feat: [core] 新增 IOBlockStorageIOSource 以公開 IOKit 讀磁碟讀/寫累計量"
```

---

### Task 4: 接入 SystemSnapshot 與 SystemSampler

**Files:**
- Modify: `Sources/GlanceCore/SystemSnapshot.swift`
- Modify: `Sources/GlanceCore/Sampling/SystemSampler.swift`

> `SystemSnapshot` 加 `diskIO` 欄(預設參數,既有呼叫端不需改)。`SystemSampler` designated init 的新 `diskIO` 參數給預設值 `nil`,故既有 `SystemSamplerTests` 兩處呼叫不會破;`convenience init()` 接真實來源;`sample()` 以 `diskIO?.sample()` 故障隔離。

- [ ] **Step 1: SystemSnapshot 加欄位**

在 `Sources/GlanceCore/SystemSnapshot.swift` 把:

```swift
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let battery: BatterySnapshot?
```

改為(在 `disk` 後加 `diskIO`):

```swift
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let diskIO: DiskIOSnapshot?
    public let battery: BatterySnapshot?
```

並把 init 簽章與賦值,從:

```swift
    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, battery: BatterySnapshot?,
                sensors: SensorSnapshot? = nil,
                topByCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.sensors = sensors
        self.topByCPU = topByCPU; self.topMemoryApps = topMemoryApps
    }
```

改為(新增 `diskIO` 預設參數,放在 `disk` 之後):

```swift
    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, diskIO: DiskIOSnapshot? = nil,
                battery: BatterySnapshot?,
                sensors: SensorSnapshot? = nil,
                topByCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.diskIO = diskIO; self.battery = battery; self.sensors = sensors
        self.topByCPU = topByCPU; self.topMemoryApps = topMemoryApps
    }
```

- [ ] **Step 2: SystemSampler 接線**

在 `Sources/GlanceCore/Sampling/SystemSampler.swift`,把成員宣告:

```swift
    private let disk: DiskSampler
    private let battery: BatterySampler
```

改為:

```swift
    private let disk: DiskSampler
    private let diskIO: DiskIOSampler?
    private let battery: BatterySampler
```

把 designated init 從:

```swift
    public init(cpu: CPUSampler, memory: MemorySampler, network: NetworkSampler,
                disk: DiskSampler, battery: BatterySampler, process: ProcessSampler,
                sensor: SensorSampler = SensorSampler()) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.process = process
        self.sensor = sensor
    }
```

改為(新增 `diskIO` 預設 `nil`,放在 `disk` 之後):

```swift
    public init(cpu: CPUSampler, memory: MemorySampler, network: NetworkSampler,
                disk: DiskSampler, diskIO: DiskIOSampler? = nil,
                battery: BatterySampler, process: ProcessSampler,
                sensor: SensorSampler = SensorSampler()) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.diskIO = diskIO; self.battery = battery; self.process = process
        self.sensor = sensor
    }
```

把 `convenience init()` 內:

```swift
            disk: DiskSampler(source: StatfsDiskSource()),
            battery: BatterySampler(source: IOKitBatterySource()),
```

改為:

```swift
            disk: DiskSampler(source: StatfsDiskSource()),
            diskIO: DiskIOSampler(source: IOBlockStorageIOSource()),
            battery: BatterySampler(source: IOKitBatterySource()),
```

把 `sample()` 內:

```swift
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
```

改為:

```swift
            network: network.sample(),
            disk: disk.sample(),
            diskIO: diskIO?.sample(),
            battery: battery.sample(),
```

- [ ] **Step 3: 全測試確認(未破壞既有)**

Run: `swift test`
Expected: 全綠(原 135 + 新增 DiskIOSampler 5 = 140 個,0 失敗)。

- [ ] **Step 4: Commit**

```bash
git add Sources/GlanceCore/SystemSnapshot.swift Sources/GlanceCore/Sampling/SystemSampler.swift
git commit -m "feat: [core] SystemSnapshot/SystemSampler 接入磁碟 I/O 取樣(故障隔離)"
```

---

### Task 5: CLI 顯示磁碟 I/O(實機驗證)

**Files:**
- Modify: `Sources/glance-cli/main.swift`

> CLI 既有結構已取樣兩次(建基準 → sleep 1s → 第二次),故 `diskIO` 速率天然非零,直接加一行即可。沿用既有「磁碟」行下方,格式比照網路行(無 `/s`、空白分隔)。

- [ ] **Step 1: 加印 I/O 行**

在 `Sources/glance-cli/main.swift` 的磁碟區塊:

```swift
if let d = s.disk {
    line("磁碟", "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes)) (\(Formatters.percent(d.usedFraction)))")
}
```

之後緊接新增:

```swift
if let io = s.diskIO {
    line("磁碟 I/O", "↑寫 \(Formatters.rateCompact(io.writeBytesPerSec)) ↓讀 \(Formatters.rateCompact(io.readBytesPerSec))")
}
```

- [ ] **Step 2: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 實機驗證**

Run: `swift run glance-cli`
Expected: 輸出含「磁碟 I/O」行,例:`磁碟 I/O    ↑寫 1.2M ↓讀 318.0K`。在系統有磁碟活動時數字 > 0(可同時跑 `find / 2>/dev/null | head` 之類製造讀取);閒置時可能為 0 或極小,屬正常。

- [ ] **Step 4: Commit**

```bash
git add Sources/glance-cli/main.swift
git commit -m "feat: [cli] glance-cli 輸出磁碟即時讀/寫速率"
```

---

### Task 6: 磁碟卡片顯示讀/寫速率

**Files:**
- Modify: `GlanceApp/Dropdown/DiskSection.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

> `DiskSection` 加 `io: DiskIOSnapshot?` 參數,在進度條與「分析空間…」按鈕之間插一行讀/寫速率(`io == nil` 整行隱藏)。`DropdownView` 多傳 `io: s?.diskIO`。`GlanceApp` 為 executable 無單元測試 target,以 `swift build` + 啟動目視為準。

- [ ] **Step 1: DiskSection 加參數與速率行**

在 `GlanceApp/Dropdown/DiskSection.swift`,把:

```swift
struct DiskSection: View {
    let snapshot: DiskSnapshot?
    @Environment(\.openWindow) private var openWindow
```

改為(加 `io` 參數):

```swift
struct DiskSection: View {
    let snapshot: DiskSnapshot?
    let io: DiskIOSnapshot?
    @Environment(\.openWindow) private var openWindow
```

並把 body 內進度條與按鈕之間:

```swift
            CustomProgressBar(value: usedFraction, color: .yellow)

            Button {
                openAnalyzerWindow()
```

改為(在進度條後、按鈕前插入速率行):

```swift
            CustomProgressBar(value: usedFraction, color: .yellow)

            if let io {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text("寫 \(Formatters.rateCompact(io.writeBytesPerSec))/s")
                    Text("·").foregroundStyle(.secondary)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("讀 \(Formatters.rateCompact(io.readBytesPerSec))/s")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            Button {
                openAnalyzerWindow()
```

- [ ] **Step 2: DropdownView 傳入 io**

在 `GlanceApp/Dropdown/DropdownView.swift` 把:

```swift
                    DiskSection(snapshot: s?.disk)
```

改為:

```swift
                    DiskSection(snapshot: s?.disk, io: s?.diskIO)
```

- [ ] **Step 3: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: 啟動目視**

Run: `swift run Glance`
Expected: app 啟動,點開下拉,磁碟卡片進度條下方出現「↑寫 X/s · ↓讀 Y/s」一行;有磁碟活動時數字變動。確認後關閉。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Dropdown/DiskSection.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 磁碟卡片顯示即時讀/寫速率"
```

---

### Task 7: README 與收尾

**Files:**
- Modify: `README.md`

> 把「磁碟即時讀寫量」從「不在 v1 範圍」移出,並在磁碟相關說明補一句。

- [ ] **Step 1: 更新「不在 v1 範圍」段**

在 `README.md` 把:

```markdown
## 不在 v1 範圍

公證、磁碟即時讀寫量——架構已預留,日後再加。
```

改為:

```markdown
## 不在 v1 範圍

公證——架構已預留,日後再加。
```

- [ ] **Step 2: 磁碟說明補一句**

在 `README.md` 點開下拉區塊說明那段(「點開有 CPU/記憶體/網路/磁碟/電池/感測器 區塊…」)結尾補充磁碟 I/O。把:

```markdown
建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池/感測器 區塊(CPU/記憶體含歷史曲線與 Top 程式)。下拉內可開「設定…」:
```

改為:

```markdown
建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池/感測器 區塊(CPU/記憶體含歷史曲線與 Top 程式;磁碟卡片含容量與即時讀/寫速率)。下拉內可開「設定…」:
```

- [ ] **Step 3: 全建置與全測試確認**

Run: `swift build && swift test`
Expected: `Build complete!` 且全測試綠(140 個,0 失敗)。

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: 磁碟即時讀/寫速率落地,移出 v1 範圍外清單"
```

---

## 自審結果

- **Spec 覆蓋**:
  - 資料層(DiskIOSnapshot/Sampler/Bridge)→ Task 1/2/3。
  - 全部實體磁碟加總 → Task 3 列舉 `IOBlockStorageDriver` 不過濾。
  - SystemSnapshot `diskIO` 欄 + 故障隔離 → Task 4(預設 nil、`diskIO?.sample()`)。
  - 磁碟卡片一行讀/寫速率、nil 隱藏 → Task 6。
  - CLI 一行、雙取樣非零 → Task 5(沿用既有雙取樣結構)。
  - 單元測試(首次/差值/dt 守衛/環繞/source 失敗)→ Task 2。
  - 不在範圍(無歷史/sparkline/選單列)→ 全計畫未觸及對應檔案。
- **占位掃描**:無 TBD/TODO;每個 code step 均含完整程式碼與確切路徑/指令;Bridge 與 UI 步驟為實機/目視驗證,列出可觀察預期。
- **型別一致**:`DiskIOCounters(readBytes:writeBytes:)`、`DiskIOSnapshot(readBytesPerSec:writeBytesPerSec:)`、`DiskIOStatsSource.read()`、`DiskIOSampler(source:clock:)`、`SystemSnapshot.diskIO`、`DiskSection(snapshot:io:)` 在 Task 1–6 間一致;`Formatters.rateCompact` 為既有函式;`kIOMainPortDefault` 為 macOS 12+ 公開常數(部署目標 13/14 符合)。
- **預設參數安全**:`SystemSnapshot.init` 與 `SystemSampler.init` 新參數均含預設值,既有 `SystemSamplerTests` 兩處呼叫不受影響。
