# 磁碟 I/O 歷史曲線 + 選單列欄位 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把磁碟即時讀/寫量補上歷史曲線(下拉卡片疊圖雙線)與選單列可勾選欄位(只顯示寫入),與 CPU/記憶體/網路的呈現對齊。

**Architecture:** 完全鏡像既有「網路歷史 + 網路選單列欄位」模式。歷史進 `MetricHistory` 的 `RingBuffer<Double>`;選單列進 `MenuBarSegment`/`MenuBarText`;UI 以 ZStack 疊兩個既有 `Sparkline`(共用 `maxValue` 同尺度),`Sparkline` 元件零修改。取樣層(`DiskIOSampler`/`IOBlockStorageIOSource`/`SystemSnapshot.diskIO`)前案已落地,本案不動。

**Tech Stack:** Swift 5.9、SwiftUI、XCTest、SwiftPM(`swift test` 跑 GlanceCore)、XcodeGen + xcodebuild(GlanceApp)。

**Spec:** `docs/superpowers/specs/2026-06-16-disk-io-history-menubar-design.md`

---

## File Structure

| 檔案 | 動作 | 職責 |
| --- | --- | --- |
| `Sources/GlanceCore/History/MetricHistory.swift` | Modify | 加 `diskRead`/`diskWrite` 兩條 RingBuffer 與 record |
| `Tests/GlanceCoreTests/MetricHistoryTests.swift` | Modify | 測 diskRead/diskWrite append 與缺值記 0 |
| `Sources/GlanceCore/MenuBar/MenuBarText.swift` | Modify | `MenuBarSegment` 加 `.diskIO`、`readings` 補分支 |
| `Tests/GlanceCoreTests/MenuBarTextTests.swift` | Modify | 測 `.diskIO` 讀數(寫入速率)與 nil 略過 |
| `GlanceApp/MenuBar/MenuBarSegmentIcon.swift` | Modify | `.diskIO → "arrow.up"` |
| `GlanceApp/Settings/SettingsView.swift` | Modify | `label(.diskIO) → "磁碟讀寫"` |
| `GlanceApp/Dropdown/DiskSection.swift` | Modify | 加 `readHistory`/`writeHistory` 參數與疊圖雙線 |
| `GlanceApp/Dropdown/DropdownView.swift` | Modify | 傳 `diskRead`/`diskWrite` 歷史給 DiskSection |

> 註:`MenuBarSegment` 列舉與 `MenuBarText.readings` 同檔(`Sources/GlanceCore/MenuBar/MenuBarText.swift`)。

---

## Task 1: MetricHistory 加磁碟讀/寫歷史

**Files:**
- Modify: `Sources/GlanceCore/History/MetricHistory.swift`
- Test: `Tests/GlanceCoreTests/MetricHistoryTests.swift`

- [ ] **Step 1: 改測試 helper 讓 snapshot 可帶 diskIO**

在 `Tests/GlanceCoreTests/MetricHistoryTests.swift` 把 `snapshot(...)` helper 換成下面版本(多一個 `diskIO` 參數,預設 nil):

```swift
private func snapshot(cpu: Double, mem: Double, down: Double, up: Double,
                      pressure: MemoryPressure = .normal,
                      diskIO: DiskIOSnapshot? = nil) -> SystemSnapshot {
    SystemSnapshot(
        cpu: CPUSnapshot(totalUsage: cpu, user: cpu, system: 0, idle: 1 - cpu),
        memory: MemorySnapshot(usedBytes: UInt64(mem * 100), totalBytes: 100, swapUsedBytes: 0, pressure: pressure),
        network: NetworkSnapshot(downBytesPerSec: down, upBytesPerSec: up, totalDownBytes: 0, totalUpBytes: 0),
        disk: nil, diskIO: diskIO, battery: nil, topByCPU: [], topMemoryApps: [])
}
```

- [ ] **Step 2: 寫失敗測試**

在 `MetricHistoryTests` 加兩個測試方法:

```swift
func testRecordsDiskIORates() {
    var h = MetricHistory(capacity: 5)
    h.record(snapshot(cpu: 0, mem: 0, down: 0, up: 0,
                      diskIO: DiskIOSnapshot(readBytesPerSec: 1000, writeBytesPerSec: 200)))
    h.record(snapshot(cpu: 0, mem: 0, down: 0, up: 0,
                      diskIO: DiskIOSnapshot(readBytesPerSec: 3000, writeBytesPerSec: 400)))
    XCTAssertEqual(h.diskRead.elements, [1000, 3000])
    XCTAssertEqual(h.diskWrite.elements, [200, 400])
}

func testMissingDiskIORecordsZero() {
    var h = MetricHistory(capacity: 5)
    h.record(snapshot(cpu: 0, mem: 0, down: 0, up: 0, diskIO: nil))
    XCTAssertEqual(h.diskRead.elements, [0])
    XCTAssertEqual(h.diskWrite.elements, [0])
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `swift test --filter MetricHistoryTests`
Expected: 編譯失敗或 FAIL——`MetricHistory` 無 `diskRead`/`diskWrite` 成員。

- [ ] **Step 4: 實作 MetricHistory**

在 `Sources/GlanceCore/History/MetricHistory.swift` 加兩條 buffer。屬性宣告區(`memoryPressure` 之後)加:

```swift
    public private(set) var diskRead: RingBuffer<Double>
    public private(set) var diskWrite: RingBuffer<Double>
```

`init(capacity:)` 內(`memoryPressure = ...` 之後)加:

```swift
        diskRead = RingBuffer(capacity: capacity)
        diskWrite = RingBuffer(capacity: capacity)
```

`record(_:)` 內(`memoryPressure.append(...)` 之後)加:

```swift
        diskRead.append(snapshot.diskIO?.readBytesPerSec ?? 0)
        diskWrite.append(snapshot.diskIO?.writeBytesPerSec ?? 0)
```

- [ ] **Step 5: 跑測試確認通過**

Run: `swift test --filter MetricHistoryTests`
Expected: PASS(含既有 5 個測試 + 新增 2 個)。

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/History/MetricHistory.swift Tests/GlanceCoreTests/MetricHistoryTests.swift
git commit -m "feat: [core] MetricHistory 記錄磁碟讀/寫速率歷史"
```

---

## Task 2: MenuBarSegment 加 diskIO 欄位

**Files:**
- Modify: `Sources/GlanceCore/MenuBar/MenuBarText.swift`
- Test: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1: 改測試 helper 讓 makeSnapshot 可帶 diskIO**

在 `Tests/GlanceCoreTests/MenuBarTextTests.swift` 的 `makeSnapshot(...)` 簽名加參數 `diskIO: DiskIOSnapshot? = nil`(放在 `disk:` 之後),並在 `SystemSnapshot(...)` 建構呼叫的 `disk: disk,` 之後插入 `diskIO: diskIO,`。改完的簽名與建構區開頭:

```swift
    private func makeSnapshot(
        cpuUsage: Double = 0.23,
        memoryUsedFraction: Double = 0.61,
        networkDownBytesPerSec: Double = 2_202_009,
        disk: DiskSnapshot? = nil,
        diskIO: DiskIOSnapshot? = nil,
        battery: BatteryStats? = nil,
        sensors: SensorSnapshot? = nil
    ) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpuUsage, user: cpuUsage, system: 0, idle: 1 - cpuUsage),
            memory: MemorySnapshot(
                usedBytes: UInt64(memoryUsedFraction * 100),
                totalBytes: 100,
                swapUsedBytes: 0,
                pressure: .normal
            ),
            network: NetworkSnapshot(
                downBytesPerSec: networkDownBytesPerSec,
                upBytesPerSec: 0,
                totalDownBytes: 0,
                totalUpBytes: 0
            ),
            disk: disk,
            diskIO: diskIO,
            battery: battery,
            sensors: sensors,
            topByCPU: [],
            topMemoryApps: []
        )
    }
```

- [ ] **Step 2: 寫失敗測試**

在 `MenuBarTextTests` 加兩個測試方法:

```swift
func testDiskIOReadingShowsWriteRate() {
    let snapshot = makeSnapshot(diskIO: DiskIOSnapshot(readBytesPerSec: 300_000, writeBytesPerSec: 1_258_291))
    let readings = MenuBarText.readings(snapshot: snapshot, segments: [.diskIO])
    XCTAssertEqual(readings, [
        SegmentReading(segment: .diskIO, value: "1.2M", status: .normal),
    ])
}

func testDiskIOReadingSkippedWhenAbsent() {
    let readings = MenuBarText.readings(snapshot: makeSnapshot(diskIO: nil), segments: [.diskIO])
    XCTAssertEqual(readings, [])
}
```

> 註:`Formatters.rateCompact(1_258_291)` == `"1.2M"`(與既有網路測試 `2_202_009 → "2.1M"` 同一格式器)。

- [ ] **Step 3: 跑測試確認失敗**

Run: `swift test --filter MenuBarTextTests`
Expected: 編譯失敗——`MenuBarSegment` 無 `.diskIO`。

- [ ] **Step 4: 實作列舉 case 與 readings 分支**

在 `Sources/GlanceCore/MenuBar/MenuBarText.swift`:

列舉加 `diskIO`(放在 `disk` 之後):

```swift
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, diskIO, battery, cpuTemp, power
}
```

`MenuBarText.readings` 的 `switch seg` 內,在 `.disk` 分支之後加:

```swift
            case .diskIO:
                if let io = snapshot.diskIO {
                    result.append(SegmentReading(
                        segment: .diskIO,
                        value: Formatters.rateCompact(io.writeBytesPerSec),
                        status: .normal
                    ))
                }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `swift test --filter MenuBarTextTests`
Expected: PASS。

- [ ] **Step 6: 跑全套件確認無回歸**

Run: `swift test`
Expected: 全綠(`MenuBarDisplayModeTests` 等若有遍歷 `allCases` 的測試仍應通過,因 `.diskIO` 不影響其斷言邏輯)。

- [ ] **Step 7: Commit**

```bash
git add Sources/GlanceCore/MenuBar/MenuBarText.swift Tests/GlanceCoreTests/MenuBarTextTests.swift
git commit -m "feat: [core] 選單列新增磁碟讀寫欄位(顯示寫入速率)"
```

---

## Task 3: GlanceApp 補選單列欄位圖示與標籤

新增列舉 case 後,GlanceApp 兩處對 `MenuBarSegment` 的窮舉 switch 會編譯失敗,本任務補齊。無 GlanceApp test target,以 xcodebuild 編譯驗證。

**Files:**
- Modify: `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`
- Modify: `GlanceApp/Settings/SettingsView.swift`

- [ ] **Step 1: 補圖示**

在 `GlanceApp/MenuBar/MenuBarSegmentIcon.swift` 的 switch,於 `.disk` 之後加:

```swift
        case .diskIO:  return "arrow.up"
```

- [ ] **Step 2: 補設定標籤**

在 `GlanceApp/Settings/SettingsView.swift` 的 `label(_:)` switch,於 `.disk` 之後加:

```swift
        case .diskIO:  return "磁碟讀寫"
```

- [ ] **Step 3: 產生專案並編譯**

Run:
```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED(兩處窮舉 switch 補齊後不再報 "switch must be exhaustive")。

- [ ] **Step 4: Commit**

```bash
git add GlanceApp/MenuBar/MenuBarSegmentIcon.swift GlanceApp/Settings/SettingsView.swift
git commit -m "feat: [app] 選單列磁碟讀寫欄位補圖示與設定標籤"
```

---

## Task 4: 磁碟卡片疊圖雙線曲線

**Files:**
- Modify: `GlanceApp/Dropdown/DiskSection.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1: DiskSection 加參數與雙線**

在 `GlanceApp/Dropdown/DiskSection.swift`,於 `let io: DiskIOSnapshot?` 之後加兩個參數:

```swift
    let readHistory: [Double]
    let writeHistory: [Double]
```

在 `body` 內既有讀寫文字行的 `if let io { ... }` 區塊**之後**、`Button { openAnalyzerWindow() }` **之前**,插入疊圖雙線曲線:

```swift
            let ioMax = max(readHistory.max() ?? 0, writeHistory.max() ?? 0, 1)
            ZStack {
                Sparkline(values: readHistory,  maxValue: ioMax, color: .yellow.opacity(0.45))
                Sparkline(values: writeHistory, maxValue: ioMax, color: .yellow)
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
```

> `ioMax` 共用讓兩線同尺度可比;`max(..., 1)` 防全 0 時除零(兩線貼底)。

- [ ] **Step 2: DropdownView 傳歷史**

在 `GlanceApp/Dropdown/DropdownView.swift`,把 `DiskSection(snapshot: s?.disk, io: s?.diskIO)` 改成:

```swift
                    DiskSection(snapshot: s?.disk, io: s?.diskIO,
                                readHistory: store.history.diskRead.elements,
                                writeHistory: store.history.diskWrite.elements)
```

- [ ] **Step 3: 編譯**

Run:
```bash
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 實機目視驗收**

Run:
```bash
swift run glance-cli   # 確認 I/O 那行有讀/寫數值(取樣層正常)
```
然後啟動 GlanceApp(`open` 編譯產物的 `Glance.app`),目視確認:
1. 下拉磁碟卡片在讀寫文字行下方出現雙線曲線(寫=實黃線、讀=淡黃線),有讀寫活動(如複製大檔)時曲線起伏。
2. 設定 →「選單列欄位」出現「磁碟讀寫」可勾選項;勾選後選單列出現 `↑` + 寫入速率。

> 參考 [[verify-by-launching-app]]:test/build 全綠仍須實機啟動確認不閃退、UI 正常。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Dropdown/DiskSection.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 磁碟卡片顯示讀/寫即時曲線(疊圖雙線、同尺度)"
```

---

## Task 5: 更新 README 與收尾

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 更新 README 描述**

在 `README.md`「選單列 App」段,把磁碟卡片描述補上歷史曲線,並在「選單列欄位」清單加入「磁碟讀寫」。具體:
- 第 45 行附近「磁碟卡片含容量與即時讀/寫速率」→ 改為「磁碟卡片含容量、即時讀/寫速率與讀寫歷史曲線」。
- 第 50 行「選單列欄位:CPU/記憶體/網路/磁碟/電池/CPU 溫度/功耗」→ 在「磁碟」後加「/磁碟讀寫」。

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: 磁碟讀寫歷史曲線與選單列欄位落地,更新 README"
```

---

## 完成定義

- `swift test` 全綠(含新增的 4 個 GlanceCore 測試)。
- `xcodebuild ... build` BUILD SUCCEEDED。
- 實機:下拉磁碟卡片有讀寫雙線曲線;設定可勾選「磁碟讀寫」選單列欄位並顯示寫入速率。
- README 反映新功能。
