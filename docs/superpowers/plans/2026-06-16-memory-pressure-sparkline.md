# 記憶體壓力當主角 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓記憶體下拉區塊以「壓力」為視覺主角:標題數字依壓力著綠/黃/紅,副標加壓力詞,歷史曲線逐段依壓力著色。

**Architecture:** 資料層(GlanceCore)新增壓力序數/標籤與一條等長的壓力歷史 RingBuffer(純函式、可單元測試);App 層新增單一配色來源 `PressureColor`,並讓 `Sparkline` 支援逐段著色、`MetricCard` 支援數字著色,最後在 `MemorySection`/`DropdownView` 接線。

**Tech Stack:** Swift 5.9、SwiftPM(`GlanceCore` library + `GlanceApp` executable)、XCTest、SwiftUI。

**測試前提:** 只有 `GlanceCore` 有測試 target(`GlanceCoreTests`)。Task 1–2(Core)走 TDD;Task 3–6(GlanceApp,SwiftUI/顏色/View)無單元測試 target,以 `swift build` 綠燈 + 實機啟動 app 視覺驗證為準(專案慣例)。

**全測試指令:** `swift test`　**全建置指令:** `swift build`

---

### Task 1: MemoryPressure 序數與顯示標籤(Core)

**Files:**
- Modify: `Sources/GlanceCore/Model/MemorySnapshot.swift`(在既有 `extension MemoryPressure` 之後追加)
- Test: `Tests/GlanceCoreTests/MemoryPressureTests.swift`

- [ ] **Step 1: 寫失敗測試**

在 `Tests/GlanceCoreTests/MemoryPressureTests.swift` 的 class 內、最後一個 `}` 之前追加:

```swift
    func testLevelOrdinal() {
        XCTAssertEqual(MemoryPressure.normal.level, 0)
        XCTAssertEqual(MemoryPressure.warning.level, 1)
        XCTAssertEqual(MemoryPressure.critical.level, 2)
    }

    func testDisplayLabel() {
        XCTAssertEqual(MemoryPressure.normal.displayLabel, "正常")
        XCTAssertEqual(MemoryPressure.warning.displayLabel, "警告")
        XCTAssertEqual(MemoryPressure.critical.displayLabel, "嚴重")
    }
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter MemoryPressureTests`
Expected: 編譯失敗 / FAIL —— `value of type 'MemoryPressure' has no member 'level'`(及 `displayLabel`)。

- [ ] **Step 3: 最小實作**

在 `Sources/GlanceCore/Model/MemorySnapshot.swift` 既有 `extension MemoryPressure { … evaluate … }` 區塊的 `evaluate(...)` 之後(同一個 extension 內)追加:

```swift
    /// 歷史編碼與分段著色用序數:normal=0 / warning=1 / critical=2。
    public var level: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    /// 下拉副標顯示字串。
    public var displayLabel: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "嚴重"
        }
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter MemoryPressureTests`
Expected: PASS（含既有 5 個 evaluate 測試 + 新增 2 個)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Model/MemorySnapshot.swift Tests/GlanceCoreTests/MemoryPressureTests.swift
git commit -m "feat: [core] MemoryPressure 新增 level 序數與 displayLabel"
```

---

### Task 2: 壓力歷史 RingBuffer(Core)

**Files:**
- Modify: `Sources/GlanceCore/History/MetricHistory.swift`
- Test: `Tests/GlanceCoreTests/MetricHistoryTests.swift`

- [ ] **Step 1: 寫失敗測試**

先把 `Tests/GlanceCoreTests/MetricHistoryTests.swift` 既有的 `snapshot(...)` helper 簽章加一個有預設值的參數(不影響既有呼叫),把這行:

```swift
    private func snapshot(cpu: Double, mem: Double, down: Double, up: Double) -> SystemSnapshot {
```

改成:

```swift
    private func snapshot(cpu: Double, mem: Double, down: Double, up: Double, pressure: MemoryPressure = .normal) -> SystemSnapshot {
```

並把 helper 內 `MemorySnapshot(...)` 的 `pressure: .normal` 改為 `pressure: pressure`:

```swift
            memory: MemorySnapshot(usedBytes: UInt64(mem * 100), totalBytes: 100, swapUsedBytes: 0, pressure: pressure),
```

接著在 class 內最後一個 `}` 之前追加兩個測試:

```swift
    func testRecordsMemoryPressureLevel() {
        var h = MetricHistory(capacity: 5)
        h.record(snapshot(cpu: 0.2, mem: 0.6, down: 0, up: 0, pressure: .normal))
        h.record(snapshot(cpu: 0.2, mem: 0.8, down: 0, up: 0, pressure: .warning))
        h.record(snapshot(cpu: 0.2, mem: 0.95, down: 0, up: 0, pressure: .critical))
        XCTAssertEqual(h.memoryPressure.elements, [0, 1, 2])
    }

    func testMissingMemoryRecordsNormalPressure() {
        var h = MetricHistory(capacity: 5)
        let empty = SystemSnapshot(cpu: nil, memory: nil, network: nil, disk: nil, battery: nil, topByCPU: [], topMemoryApps: [])
        h.record(empty)
        XCTAssertEqual(h.memoryPressure.elements, [0])
    }
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter MetricHistoryTests`
Expected: 編譯失敗 / FAIL —— `value of type 'MetricHistory' has no member 'memoryPressure'`。

- [ ] **Step 3: 最小實作**

修改 `Sources/GlanceCore/History/MetricHistory.swift`:

(a) 屬性宣告區加一條(在 `netUp` 之後):

```swift
    public private(set) var memoryPressure: RingBuffer<Double>
```

(b) `init(capacity:)` 內加一行初始化(在 `netUp = ...` 之後):

```swift
        memoryPressure = RingBuffer(capacity: capacity)
```

(c) `record(_:)` 內加一行(在 `netUp.append(...)` 之後):

```swift
        memoryPressure.append(Double(snapshot.memory?.pressure.level ?? 0))
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter MetricHistoryTests`
Expected: PASS（既有 3 個 + 新增 2 個)。

- [ ] **Step 5: 全測試回歸**

Run: `swift test`
Expected: 全綠（131 + 4 = 135 個測試,0 失敗)。

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/History/MetricHistory.swift Tests/GlanceCoreTests/MetricHistoryTests.swift
git commit -m "feat: [core] MetricHistory 新增 memoryPressure 歷史序列"
```

---

### Task 3: 壓力配色單一來源(App)

**Files:**
- Create: `GlanceApp/Dropdown/PressureColor.swift`

> 無單元測試 target(GlanceApp 為 executable);以 `swift build` 綠燈驗證。

- [ ] **Step 1: 建立配色工具**

建立 `GlanceApp/Dropdown/PressureColor.swift`:

```swift
import SwiftUI
import GlanceCore

/// 記憶體壓力的活動監視器語義色:綠=正常 / 黃=警告 / 紅=嚴重。
/// 標題數字色與 sparkline 分段色共用此唯一來源。
enum PressureColor {
    static func color(for pressure: MemoryPressure) -> Color {
        color(forLevel: pressure.level)
    }

    /// 供 sparkline 由歷史序數(0/1/2)取色。
    static func color(forLevel level: Int) -> Color {
        switch level {
        case 2: return .red
        case 1: return .yellow
        default: return .green
        }
    }
}
```

- [ ] **Step 2: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/Dropdown/PressureColor.swift
git commit -m "feat: [app] 新增記憶體壓力配色 PressureColor(綠/黃/紅)"
```

---

### Task 4: Sparkline 逐段著色(App)

**Files:**
- Modify: `GlanceApp/Components/Sparkline.swift`

> 段色取該段右端點(較新樣本)`bandColors[i+1]`;Sparkline 只收已映射好的 `[Color]`,不認識壓力語義。`bandColors == nil` 時行為與現狀完全一致(CPU/網路維持單色)。

- [ ] **Step 1: 加入可選參數**

在 `struct Sparkline` 的屬性區(`var color: Color = .green` 之後)加入:

```swift
    /// 每個資料點一色。給定時改為逐段著色(段色取右端點 bandColors[i+1]);nil 維持單色。
    var bandColors: [Color]? = nil
```

- [ ] **Step 2: body 改為分段描邊**

把 `body` 內「2. 平滑描邊折線」那段(現為單一 `smoothedPath(points:).stroke(...)`)替換成:依 `bandColors` 有無切換。將現有的:

```swift
                    // 2. 平滑描邊折線
                    smoothedPath(points: pts)
                        .stroke(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
```

替換為:

```swift
                    // 2. 平滑描邊折線:有 bandColors 則逐段著色,否則單色。
                    if let bands = bandColors, bands.count == values.count {
                        ForEach(0..<(pts.count - 1), id: \.self) { i in
                            segmentPath(from: pts[i], to: pts[i + 1])
                                .stroke(
                                    bands[i + 1],
                                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                                )
                        }
                    } else {
                        smoothedPath(points: pts)
                            .stroke(
                                LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                            )
                    }
```

- [ ] **Step 3: 新增單段路徑 helper**

在 `private func smoothedPath` 之前(或 struct 內任一處)新增:

```swift
    /// 單一段(點 p1→p2)的三次貝氏平滑路徑,與 smoothedPath 的控制點公式一致。
    private func segmentPath(from p1: CGPoint, to p2: CGPoint) -> Path {
        var path = Path()
        path.move(to: p1)
        let controlPoint1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3.0, y: p1.y)
        let controlPoint2 = CGPoint(x: p1.x + 2.0 * (p2.x - p1.x) / 3.0, y: p2.y)
        path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        return path
    }
```

- [ ] **Step 4: 建置確認**

Run: `swift build`
Expected: `Build complete!`（注意 `ForEach` 需 `values`/`pts` 在該 closure 可見;`pts` 已於 `body` 上方 `let pts = points(in: geo.size)` 取得)。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Components/Sparkline.swift
git commit -m "feat: [app] Sparkline 支援 bandColors 逐段著色(向後相容)"
```

---

### Task 5: MetricCard 數字著色(App)

**Files:**
- Modify: `GlanceApp/Dropdown/DropdownChrome.swift`

> 新增可選 `valueColor: Color? = nil`;nil 時維持現狀(預設前景色)。其他卡片不傳即不受影響。

- [ ] **Step 1: 加入屬性**

在 `struct MetricCard` 屬性區(`let status: MetricStatus?` 之後)加入:

```swift
    var valueColor: Color? = nil
```

- [ ] **Step 2: 套到 value 文字**

把 `body` 內顯示 `value` 的:

```swift
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
```

改為(尾端加一行 `.foregroundStyle`):

```swift
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(valueColor ?? .primary)
```

- [ ] **Step 3: 建置確認**

Run: `swift build`
Expected: `Build complete!`（其他 Section 未傳 `valueColor`,因有預設值不受影響)。

- [ ] **Step 4: Commit**

```bash
git add GlanceApp/Dropdown/DropdownChrome.swift
git commit -m "feat: [app] MetricCard 新增可選 valueColor(預設不變)"
```

---

### Task 6: 記憶體卡片接線(App)

**Files:**
- Modify: `GlanceApp/Dropdown/MemorySection.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1: MemorySection 接入壓力**

將 `GlanceApp/Dropdown/MemorySection.swift` 全檔改為:

```swift
import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let pressureHistory: [Double]   // 與 history 等長的壓力序數(0/1/2)
    let topApps: [AppMemoryUsage]

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        let pressure = snapshot?.pressure ?? .normal
        MetricCard(
            title: "記憶體",
            systemImage: "memorychip",
            accent: .blue,
            value: Formatters.percent(usedFraction),
            detail: memoryDetail,
            status: nil,
            valueColor: PressureColor.color(for: pressure)
        ) {
            Sparkline(
                values: history,
                maxValue: 1,
                color: .blue,
                bandColors: pressureBandColors
            )
            .frame(height: 52)
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
        return "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes)) · 壓力:\(m.pressure.displayLabel)"
    }

    /// 壓力歷史序數映射為顏色;長度與 history 不一致時回傳 nil(Sparkline 退回單色)。
    private var pressureBandColors: [Color]? {
        guard pressureHistory.count == history.count, !pressureHistory.isEmpty else { return nil }
        return pressureHistory.map { PressureColor.color(forLevel: Int($0)) }
    }
}
```

- [ ] **Step 2: DropdownView 餵入壓力歷史**

在 `GlanceApp/Dropdown/DropdownView.swift` 把 `MemorySection(...)` 呼叫:

```swift
                    MemorySection(snapshot: s?.memory,
                                  history: store.history.memory.elements,
                                  topApps: s?.topMemoryApps ?? [])
```

改為:

```swift
                    MemorySection(snapshot: s?.memory,
                                  history: store.history.memory.elements,
                                  pressureHistory: store.history.memoryPressure.elements,
                                  topApps: s?.topMemoryApps ?? [])
```

- [ ] **Step 3: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: 全測試回歸**

Run: `swift test`
Expected: 全綠（135 個,0 失敗)。

- [ ] **Step 5: 實機視覺驗證**

組 `.app` 並啟動(依專案慣例,非僅 build):

```bash
swift run Glance
```

逐項確認:
- 記憶體卡片標題數字在低壓力時為**綠色**;副標顯示「… · 壓力:正常」。
- sparkline 線色為綠;隨時間維持連續曲線(無破圖)。
- 人為製造記憶體壓力(開大量分頁 / 大型 app)使用量升高時,數字與線色應轉**黃**,副標轉「警告」;極高時轉**紅**/「嚴重」。
- 其他卡片(CPU/網路/磁碟/電池/感測器)外觀與先前一致(未受 `valueColor`/`bandColors` 影響)。

- [ ] **Step 6: Commit**

```bash
git add GlanceApp/Dropdown/MemorySection.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 記憶體卡片以壓力著色(數字+曲線)並加壓力副標"
```

---

## 自審結果

- **Spec 覆蓋**:壓力序數/標籤(Task 1)、壓力歷史(Task 2)、配色來源(Task 3)、sparkline 逐段著色(Task 4)、數字著色(Task 5)、副標+接線(Task 6)— spec 各節皆有對應 task。「不在範圍」項目(連續分數、改門檻、purge、Available 拆解)均未納入。
- **占位掃描**:無 TBD/TODO;每個 code step 皆含完整程式碼與確切路徑/指令。
- **型別一致**:`level: Int`(Task 1)被 Task 2 `memory?.pressure.level` 與 Task 6 `PressureColor.color(forLevel:)` 一致使用;`displayLabel`(Task 1)被 Task 6 副標使用;`memoryPressure`(Task 2)被 Task 6 `store.history.memoryPressure.elements` 一致使用;`bandColors`(Task 4)與 `valueColor`(Task 5)的呼叫端參數名與 Task 6 一致;`RingBuffer` 對外用 `.elements`(非 `.values`)。

---

## 後續待辦(merge 後 follow-up)

> 已於 master `07aa386` 合併完成。以下為最終整體審查列為「非阻擋」的後續項,擇日處理。
>
> ✅ 四項已於 `feat/memory-pressure-followup`(計畫見 `2026-06-16-memory-pressure-followup.md`)完成並實機目視驗證通過。

- [x] **無障礙(VoiceOver)**:目前壓力主要靠「標題數字顏色 + 副標文字」傳達,顏色對 VoiceOver 無語義。可在 `MetricCard`/`MemorySection` 加 `accessibilityLabel`(例:`記憶體 79% 壓力警告`),讓壓力不僅靠顏色。`MemorySection.swift` 約 line 20/47。
- [x] **淺色模式對比**:`PressureColor` 的 `Color.yellow`(警告)在 macOS Light Mode 卡片淺底下對比接近 WCAG AA 邊緣。可改用 `Color(.systemOrange)` 或調整亮度。檔案 `GlanceApp/Dropdown/PressureColor.swift`。
- [x] **實機目視驗證**:結構已由 build/測試/啟動冒煙驗證,但壓力色的實際綠→黃→紅切換尚未在執行中下拉目視確認。開大型 app 製造記憶體壓力後,確認標題數字、副標、sparkline 三者同步轉色。
- [x] **(可選)防呆 assert**:`PressureColor.color(forLevel:)` 對非 0/1/2 的輸入靜默回綠;若日後 `memoryPressure` 改存連續值,可在 `default` 加 `assertionFailure`(debug-only)以早期發現誤用。
