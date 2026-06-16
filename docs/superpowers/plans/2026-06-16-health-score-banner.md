# Health Score 健康分數 + 下拉放大 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Glance 下拉視窗頂端加入一個 0–100 系統健康分數橫幅,並把下拉視窗加寬、各區塊等比放大。

**Architecture:** 計分邏輯為 `GlanceCore` 的純函式(`HealthScoreCalculator.evaluate(_:)`),吃既有 `SystemSnapshot`、輸出 `HealthScore`,可完整單元測試。UI 端新增 `HealthBanner` view 插入 `DropdownView`,並調整視窗寬度與 `MetricCard`/各 section 的尺寸。計分演算法沿用 [tw93/mole](https://github.com/tw93/mole) `cmd/status/metrics_health.go`,但略過磁碟 I/O 與開機時長(Glance 未取樣)。

**Tech Stack:** Swift 5.9、SPM(`swift build` / `swift test`)、SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-06-16-health-score-banner-design.md`

---

## File Structure

- Create `Sources/GlanceCore/Health/HealthScore.swift` — 結果模型 `HealthScore` 與分段 `HealthBand`(純資料,不依賴 SwiftUI)。
- Create `Sources/GlanceCore/Health/HealthScoreCalculator.swift` — 純函式計分,所有扣分邏輯集中於此。
- Create `Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift` — 計分與分段單元測試。
- Create `GlanceApp/Dropdown/HealthBanner.swift` — 頂端橫幅 view + `HealthBand` 顏色對應(SwiftUI 端)。
- Modify `GlanceApp/Dropdown/DropdownView.swift` — 插入橫幅、視窗加寬、header/pill 放大。
- Modify `GlanceApp/Dropdown/DropdownChrome.swift` — `MetricCard` 字級/圖示/內距放大(一處影響全部 section)。
- Modify `GlanceApp/Dropdown/CPUSection.swift`、`MemorySection.swift`、`NetworkSection.swift` — sparkline 高度 42 → 52。

---

## Task 1: HealthScore 模型與 HealthBand 分段

**Files:**
- Create: `Sources/GlanceCore/Health/HealthScore.swift`
- Test: `Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift`(本 Task 先建檔,只放 band 測試)

- [ ] **Step 1: 寫失敗測試(band 分段邊界)**

建立 `Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class HealthScoreCalculatorTests: XCTestCase {
    func testBandBoundaries() {
        XCTAssertEqual(HealthBand.from(score: 100), .excellent)
        XCTAssertEqual(HealthBand.from(score: 85), .excellent)
        XCTAssertEqual(HealthBand.from(score: 84), .good)
        XCTAssertEqual(HealthBand.from(score: 65), .good)
        XCTAssertEqual(HealthBand.from(score: 64), .fair)
        XCTAssertEqual(HealthBand.from(score: 45), .fair)
        XCTAssertEqual(HealthBand.from(score: 44), .needsAttention)
        XCTAssertEqual(HealthBand.from(score: 0), .needsAttention)
    }

    func testBandLabels() {
        XCTAssertEqual(HealthBand.excellent.label, "系統健康")
        XCTAssertEqual(HealthBand.good.label, "良好")
        XCTAssertEqual(HealthBand.fair.label, "普通")
        XCTAssertEqual(HealthBand.needsAttention.label, "注意")
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter HealthScoreCalculatorTests`
Expected: 編譯失敗(`HealthBand` / `HealthScore` 未定義)。

- [ ] **Step 3: 建立模型**

建立 `Sources/GlanceCore/Health/HealthScore.swift`:

```swift
/// 系統健康分數結果:0...100 分與對應分段。
public struct HealthScore: Equatable {
    public let value: Int          // 0...100
    public let band: HealthBand

    public init(value: Int, band: HealthBand) {
        self.value = value
        self.band = band
    }
}

/// 分數分段(門檻沿用 mole)。label 為中文顯示字串;顏色對應在 GlanceApp 端。
public enum HealthBand: Equatable {
    case excellent      // >= 85
    case good           // 65...84
    case fair           // 45...64
    case needsAttention // < 45

    public var label: String {
        switch self {
        case .excellent: return "系統健康"
        case .good: return "良好"
        case .fair: return "普通"
        case .needsAttention: return "注意"
        }
    }

    public static func from(score: Int) -> HealthBand {
        if score >= 85 { return .excellent }
        if score >= 65 { return .good }
        if score >= 45 { return .fair }
        return .needsAttention
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter HealthScoreCalculatorTests`
Expected: PASS(`testBandBoundaries`、`testBandLabels`)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Health/HealthScore.swift Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift
git commit -m "feat: [core] 新增 HealthScore 模型與 HealthBand 分段"
```

---

## Task 2: HealthScoreCalculator 計分

**Files:**
- Create: `Sources/GlanceCore/Health/HealthScoreCalculator.swift`
- Test: `Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift`(新增計分測試)

- [ ] **Step 1: 寫失敗測試(計分)**

在 `HealthScoreCalculatorTests` 類別內新增以下 helper 與測試。helper 用既有 model 的 public init 組出 `SystemSnapshot`:

```swift
    // MARK: - helpers

    private func snapshot(
        cpuFraction: Double = 0.1,
        memFraction: Double = 0.3,
        pressure: MemoryPressure = .normal,
        diskFraction: Double = 0.3,
        cpuTemp: Double? = 40,
        battery: BatterySnapshot? = nil
    ) -> SystemSnapshot {
        let cpu = CPUSnapshot(totalUsage: cpuFraction, user: cpuFraction, system: 0, idle: 1 - cpuFraction)
        let total: UInt64 = 16_000_000_000
        let mem = MemorySnapshot(
            totalBytes: total,
            usedBytes: UInt64(Double(total) * memFraction),
            swapUsedBytes: 0,
            pressure: pressure
        )
        let disk = DiskSnapshot(
            totalBytes: total,
            usedBytes: UInt64(Double(total) * diskFraction)
        )
        let sensors = SensorSnapshot(cpuTemperature: cpuTemp)
        return SystemSnapshot(
            cpu: cpu, memory: mem, network: nil, disk: disk,
            battery: battery, sensors: sensors,
            topByCPU: [], topMemoryApps: []
        )
    }

    // MARK: - scoring

    func testAllNormalScoresHundred() {
        let result = HealthScoreCalculator.evaluate(snapshot())
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.band, .excellent)
    }

    func testCPUAtHighBoundaryDeductsFullHalfWeight() {
        // usage 85% (== high 門檻,未超過)→ 半權重公式 = 15 * (85-50)/(85-50) = 15
        let result = HealthScoreCalculator.evaluate(snapshot(cpuFraction: 0.85))
        XCTAssertEqual(result.value, 85)
    }

    func testMemoryCriticalPressureDeductsFifteen() {
        // 記憶體使用 50%(無基礎扣分)+ critical 壓力 −15
        let result = HealthScoreCalculator.evaluate(snapshot(memFraction: 0.5, pressure: .critical))
        XCTAssertEqual(result.value, 85)
    }

    func testMemoryWarningPressureDeductsFive() {
        let result = HealthScoreCalculator.evaluate(snapshot(memFraction: 0.5, pressure: .warning))
        XCTAssertEqual(result.value, 95)
    }

    func testDiskAlmostFullDeductsTowardFullWeight() {
        // 磁碟 95% (>93 crit) → 20 * (95-80)/(100-80) = 15
        let result = HealthScoreCalculator.evaluate(snapshot(diskFraction: 0.95))
        XCTAssertEqual(result.value, 85)
    }

    func testThermalAboveHighDeductsFullWeight() {
        // CPU 溫度 90 (>85) → 滿權重 15
        let result = HealthScoreCalculator.evaluate(snapshot(cpuTemp: 90))
        XCTAssertEqual(result.value, 85)
    }

    func testBatteryDangerDeductsFive() {
        let bat = BatterySnapshot(isPresent: true, chargeFraction: 0.9, isCharging: false,
                                  cycleCount: 950, healthFraction: 0.5)
        let result = HealthScoreCalculator.evaluate(snapshot(battery: bat))
        XCTAssertEqual(result.value, 95)
    }

    func testNilMetricsDoNotCrashOrDeduct() {
        // 無溫度、無電池 → 該項不扣
        let cpu = CPUSnapshot(totalUsage: 0.1, user: 0.1, system: 0, idle: 0.9)
        let snap = SystemSnapshot(cpu: cpu, memory: nil, network: nil, disk: nil,
                                  battery: nil, sensors: nil, topByCPU: [], topMemoryApps: [])
        let result = HealthScoreCalculator.evaluate(snap)
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.band, .excellent)
    }

    func testHeavyLoadLandsInNeedsAttention() {
        let bat = BatterySnapshot(isPresent: true, chargeFraction: 0.5, isCharging: false,
                                  cycleCount: 950, healthFraction: 0.5)
        let result = HealthScoreCalculator.evaluate(
            snapshot(cpuFraction: 1.0, memFraction: 1.0, pressure: .critical,
                     diskFraction: 1.0, cpuTemp: 100, battery: bat)
        )
        XCTAssertEqual(result.band, .needsAttention)
        XCTAssertGreaterThanOrEqual(result.value, 0)
        XCTAssertLessThan(result.value, 45)
    }
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter HealthScoreCalculatorTests`
Expected: 編譯失敗(`HealthScoreCalculator` 未定義)。

- [ ] **Step 3: 實作計分**

建立 `Sources/GlanceCore/Health/HealthScoreCalculator.swift`。權重/門檻/公式逐項對應 mole `metrics_health.go`:

```swift
/// 用既有 SystemSnapshot 算系統健康分數。純函式、無副作用。
/// 演算法沿用 tw93/mole metrics_health.go,略過磁碟 I/O 與開機時長(Glance 未取樣)。
public enum HealthScoreCalculator {

    // 權重
    private static let cpuWeight = 30.0
    private static let memWeight = 25.0
    private static let diskWeight = 20.0
    private static let thermalWeight = 15.0

    // 門檻
    private static let cpuNormal = 50.0,  cpuHigh = 85.0
    private static let memNormal = 70.0,  memHigh = 88.0
    private static let diskWarn = 80.0,   diskCrit = 93.0
    private static let thermalNormal = 65.0, thermalHigh = 85.0

    public static func evaluate(_ snapshot: SystemSnapshot) -> HealthScore {
        var score = 100.0

        if let cpu = snapshot.cpu {
            score -= cpuPenalty(cpu.totalUsage * 100)
        }

        if let mem = snapshot.memory {
            score -= memPenalty(mem.usedFraction * 100)
            switch mem.pressure {
            case .warning: score -= 5
            case .critical: score -= 15
            case .normal: break
            }
        }

        if let disk = snapshot.disk {
            score -= diskPenalty(disk.usedFraction * 100)
        }

        if let temp = snapshot.sensors?.cpuTemperature, temp > 0 {
            score -= thermalPenalty(temp)
        }

        if let battery = snapshot.battery, battery.isPresent {
            score -= batteryPenalty(cycles: battery.cycleCount, health: battery.healthFraction)
        }

        let clamped = Int(max(0, min(100, score)).rounded())
        return HealthScore(value: clamped, band: HealthBand.from(score: clamped))
    }

    // mole CPU:超過 high 用全權重 * (u-normal)/high;否則半權重線性內插。
    private static func cpuPenalty(_ u: Double) -> Double {
        guard u > cpuNormal else { return 0 }
        if u > cpuHigh { return cpuWeight * (u - cpuNormal) / cpuHigh }
        return (cpuWeight / 2) * (u - cpuNormal) / (cpuHigh - cpuNormal)
    }

    // mole Memory:超過 high 用全權重 * (u-normal)/normal;否則半權重線性內插。
    private static func memPenalty(_ u: Double) -> Double {
        guard u > memNormal else { return 0 }
        if u > memHigh { return memWeight * (u - memNormal) / memNormal }
        return (memWeight / 2) * (u - memNormal) / (memHigh - memNormal)
    }

    // mole Disk:超過 crit 用全權重 * (u-warn)/(100-warn);否則半權重線性內插。
    private static func diskPenalty(_ u: Double) -> Double {
        guard u > diskWarn else { return 0 }
        if u > diskCrit { return diskWeight * (u - diskWarn) / (100 - diskWarn) }
        return (diskWeight / 2) * (u - diskWarn) / (diskCrit - diskWarn)
    }

    // mole Thermal:超過 high 直接滿權重;否則線性內插至滿權重。
    private static func thermalPenalty(_ t: Double) -> Double {
        guard t > thermalNormal else { return 0 }
        if t > thermalHigh { return thermalWeight }
        return thermalWeight * (t - thermalNormal) / (thermalHigh - thermalNormal)
    }

    // mole Battery:循環>900 或健康度<60% → −5;循環>800 或健康度<80% → −2。
    private static func batteryPenalty(cycles: Int?, health: Double?) -> Double {
        let cap = health.map { $0 * 100 }
        let cycle = cycles ?? 0
        if cycle > 900 || (cap.map { $0 < 60 } ?? false) { return 5 }
        if cycle > 800 || (cap.map { $0 < 80 } ?? false) { return 2 }
        return 0
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter HealthScoreCalculatorTests`
Expected: PASS(全部 11 個測試)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Health/HealthScoreCalculator.swift Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift
git commit -m "feat: [core] HealthScoreCalculator 計分(沿用 mole 演算法)"
```

---

## Task 3: HealthBanner 橫幅 view 與整合

**Files:**
- Create: `GlanceApp/Dropdown/HealthBanner.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`(header 與 ScrollView 之間插入橫幅)

- [ ] **Step 1: 建立 HealthBanner view**

建立 `GlanceApp/Dropdown/HealthBanner.swift`:

```swift
import SwiftUI
import GlanceCore

/// 下拉頂端的系統健康橫幅:彩色圓點 + 標籤 + 大號分數。
/// snapshot == nil(尚未取樣)時顯示灰色「—」。
struct HealthBanner: View {
    let snapshot: SystemSnapshot?

    var body: some View {
        let score = snapshot.map { HealthScoreCalculator.evaluate($0) }
        let color = score?.band.tint ?? .secondary

        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(score?.band.label ?? "尚未取樣")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(score.map { String($0.value) } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        }
    }
}

extension HealthBand {
    /// 分段對應顏色:綠 / 淡綠 / 橘 / 紅。
    var tint: Color {
        switch self {
        case .excellent: return .green
        case .good: return Color(red: 0.40, green: 0.78, blue: 0.45)
        case .fair: return .orange
        case .needsAttention: return .red
        }
    }
}
```

- [ ] **Step 2: 在 DropdownView 插入橫幅**

修改 `GlanceApp/Dropdown/DropdownView.swift` 的 `body`,在 `header(...)` 區塊與 `ScrollView` 之間插入橫幅。將:

```swift
            header(snapshot: s)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: true) {
```

改為:

```swift
            header(snapshot: s)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            HealthBanner(snapshot: s)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: true) {
```

- [ ] **Step 3: 建置確認編譯通過**

Run: `swift build`
Expected: Build complete(無錯誤)。

- [ ] **Step 4: 實機驗證**

依記憶 [[verify-by-launching-app]],build/test 綠不代表執行正常。手動啟動 app:

```bash
swift build -c release
```

組出 .app 或直接執行產物啟動,點開選單列下拉,確認:
- 頂端出現健康橫幅,顯示分數與對應顏色(高負載時轉橘/紅)。
- 尚未取樣的一瞬間顯示灰色「尚未取樣 / —」,取樣後更新為分數。
- 橫幅在 header 下、捲動區上,不隨內容捲動。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Dropdown/HealthBanner.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 下拉頂端新增系統健康分數橫幅"
```

---

## Task 4: 下拉視窗加寬與各區塊等比放大

**Files:**
- Modify: `GlanceApp/Dropdown/DropdownView.swift`(視窗寬度、header、summaryPill)
- Modify: `GlanceApp/Dropdown/DropdownChrome.swift`(MetricCard 字級/圖示/內距)
- Modify: `GlanceApp/Dropdown/CPUSection.swift`、`MemorySection.swift`、`NetworkSection.swift`(sparkline 高度)

- [ ] **Step 1: 加寬視窗**

修改 `GlanceApp/Dropdown/DropdownView.swift`,將 `.frame(width: 340)` 改為:

```swift
        .frame(width: 440)
```

- [ ] **Step 2: 放大 header 與 summaryPill**

在同檔 `summaryPill` 內,將:

```swift
        .frame(width: 48, height: 32)
```

改為:

```swift
        .frame(width: 56, height: 36)
```

並把 `summaryPill` 內 `Text(value)` 的 `.font(.system(size: 11, ...))` 改為 `size: 12`,標題 `Text(title)` 的 `size: 9` 改為 `size: 10`。`header` 內的 `Text("Glance")` 由 `size: 16` 改為 `size: 18`。

- [ ] **Step 3: 放大 MetricCard**

修改 `GlanceApp/Dropdown/DropdownChrome.swift` 的 `MetricCard.body`,逐項調整尺寸:

- 圖示 `Image(systemName:)` 的 `.font(.system(size: 13, ...))` → `size: 15`;`.frame(width: 26, height: 26)` → `width: 30, height: 30`。
- 標題 `Text(title)` 的 `.font(.system(size: 13, ...))` → `size: 15`。
- 細節 `Text(detail)` 的 `.font(.system(size: 10.5))` → `size: 12`。
- 數值 `Text(value)` 的 `.font(.system(size: 16, ...))` → `size: 18`。
- 卡片 `.padding(12)` → `.padding(14)`。
- 外層 `VStack(alignment: .leading, spacing: 10)` → `spacing: 12`。

- [ ] **Step 4: 放大 sparkline 高度**

在 `CPUSection.swift`、`MemorySection.swift`、`NetworkSection.swift` 三個檔中,各有一處 `.frame(height: 42)`,改為:

```swift
                .frame(height: 52)
```

- [ ] **Step 5: 建置確認編譯通過**

Run: `swift build`
Expected: Build complete(無錯誤)。

- [ ] **Step 6: 實機驗證**

依 [[verify-by-launching-app]] 啟動 app,確認:
- 下拉視窗加寬至約 440pt,字級/圖表/間距明顯放大、留白舒適(對齊 brainstorm 方案 B)。
- Top 程式列、各 section 標題與數值清晰不擠。
- 捲動行為與「視窗約螢幕可視高度 4/5」上限維持正常(`scrollHeight` 未改)。
- 在內建螢幕/瀏海機型下寬度可接受(必要時於此微調寬度數值)。

- [ ] **Step 7: Commit**

```bash
git add GlanceApp/Dropdown/DropdownView.swift GlanceApp/Dropdown/DropdownChrome.swift \
        GlanceApp/Dropdown/CPUSection.swift GlanceApp/Dropdown/MemorySection.swift GlanceApp/Dropdown/NetworkSection.swift
git commit -m "feat: [app] 下拉視窗加寬至 440pt 並等比放大各區塊"
```

---

## 完成後

- 更新 `README.md`「選單列 App」段落,補一句下拉頂端有系統健康分數橫幅。(非必要,可併入最後一次 commit)
- 階段二(清理功能)、階段三(App 解除安裝器)另開 spec 與 plan。
```
