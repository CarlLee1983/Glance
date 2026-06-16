# Health Score 健康分數 + 下拉放大(階段一)設計

**日期**:2026-06-16
**參考**:[tw93/mole](https://github.com/tw93/mole) 的 `mo status` 健康分數(`cmd/status/metrics_health.go`)

## 背景與目標

Glance 目前是純監控的 macOS 選單列 App。借鑑 mole 的功能,規劃分三階段擴張(依優先序):

1. **階段一(本 spec)**:Health Score 健康分數
2. 階段二:清理類功能(快取/垃圾/開發殘檔,需刪檔安全機制)
3. 階段三:App 解除安裝器

本 spec 只涵蓋**階段一**,且因 brainstorm 過程衍生需求,階段一包含兩件相關工作:

- **A. Health Score**:用既有取樣資料算一個 0–100 健康分數,顯示在下拉視窗頂端橫幅。
- **B. 下拉放大**:將下拉視窗從 340pt 加寬到約 440pt,並等比放大各區塊字級/圖表/間距(brainstorm 選定方案 B + 放大程度選項 2)。

非目標:選單列不顯示分數(僅放下拉頂端);不顯示各項扣分明細(僅總分+標籤);不抽共用尺寸常數。

## A. Health Score

### 計分演算法(沿用 mole 精神)

從 100 分起,各項依使用率往下扣,夾在 0–100。權重與門檻沿用 mole:

| 項目 | 權重 | 門檻 | Glance 資料來源 |
| --- | --- | --- | --- |
| CPU | 30 | 50% 起扣、85% 滿扣 | `cpu.totalUsage`(0…1 → ×100) |
| 記憶體 | 25 | 70% 起扣、88% 滿扣 | `memory.usedFraction` |
| 記憶體壓力 | 額外 −5 / −15 | warn / critical | `memory.pressure` |
| 磁碟 | 20 | 80% 起扣、93% 滿扣 | `disk.usedFraction` |
| CPU 溫度 | 15 | 65°C 起扣、85°C 滿扣 | `sensors.cpuTemperature` |
| 電池 | −2 / −5 | 循環 >800/>900 或健康度 <80%/<60% | `battery.cycleCount` / `healthFraction` |

**扣分公式**(沿用 mole 兩段式,以 CPU 為例):

- `usage <= 起扣門檻` → 不扣
- `起扣 < usage <= 滿扣` → `(權重/2) * (usage - 起扣) / (滿扣 - 起扣)`
- `usage > 滿扣` → mole 對 CPU/記憶體用 `權重 * (usage - 起扣) / 滿扣`(可超過權重值,靠最後 clamp 收斂);磁碟用 `權重 * (usage - 起扣) / (100 - 起扣)`;溫度則直接給滿權重 15。實作以 mole `metrics_health.go` 逐項對應為準。

記憶體壓力:`warn` 額外 −5、`critical` 額外 −15。

電池(僅在有電池時):循環 >900 或健康度 <60% → −5;循環 >800 或健康度 <80% → −2。

### 與 mole 的刻意差異

- **磁碟 I/O(mole 權重 10)略過**:Glance 未取樣 disk read/write 速率。滿分仍 100,只是分數不會因 I/O 下降。
- **開機時長扣分(mole −1/−3)略過**:Glance 未取樣 uptime,需新增 sampler,影響僅 1–3 分,留待日後。
- **故障隔離**:任一指標取樣失敗為 `nil` 時,該項不扣分、不崩潰(符合 Glance 既有 `SystemSnapshot` 各欄可 nil 的設計)。

### 分數分段

夾在 0–100 後,對應四段(沿用 mole 門檻):

| 分數 | 標籤(band.label) | 顏色 |
| --- | --- | --- |
| ≥85 | 系統健康 | 綠 |
| 65–84 | 良好 | 綠(較淡) |
| 45–64 | 普通 | 橘 |
| <45 | 注意 | 紅 |

### 模組結構(GlanceCore,純邏輯)

- `Sources/GlanceCore/Health/HealthScore.swift`
  ```swift
  public struct HealthScore: Equatable {
      public let value: Int          // 0...100
      public let band: HealthBand
  }
  public enum HealthBand: Equatable {
      case excellent, good, fair, needsAttention
      public var label: String { /* 系統健康 / 良好 / 普通 / 注意 */ }
      public static func from(score: Int) -> HealthBand
  }
  ```
- `Sources/GlanceCore/Health/HealthScoreCalculator.swift`
  ```swift
  public enum HealthScoreCalculator {
      public static func evaluate(_ snapshot: SystemSnapshot) -> HealthScore
  }
  ```
  完全無副作用,所有扣分邏輯集中於此。

## B. 下拉放大

- `DropdownView` 視窗寬度 `340` → 約 `440`pt。
- 各 section 等比放大:字級、圖表高度、列距/內距。涉及檔案:
  `CPUSection`、`MemorySection`、`NetworkSection`、`DiskSection`、`BatterySection`、`SensorsSection`、以及 `DropdownView` 的 header/footer/summaryPill。
- 不抽共用常數(brainstorm 選項 2,非 3);直接於各檔調整數值,維持現有寫法風格。
- `scrollHeight` 邏輯(視窗約螢幕可視高度 4/5、固定高度)維持不變。

### Health 橫幅 UI

- 新檔 `GlanceApp/Dropdown/HealthBanner.swift`。
- 位置:`DropdownView` 的 `header` 與 `ScrollView` 之間,固定不捲動。
- 內容(分數 + 文字標籤 + 顏色):左側彩色圓點 + band.label,右側大號分數(`monospacedDigit`)。
- 整條背景帶 band 顏色淡填充 + 細邊框(呼應現有 pill 風格)。
- `snapshot == nil`(尚未取樣)→ 灰色「—」,不顯示分數。
- 寬度撐滿視窗內距,高度約 36–40pt。
- band → SwiftUI Color 的對應放在 GlanceApp 端(UI 擴充或 banner 內),Core 不依賴 SwiftUI。

## 測試與驗收

**單元測試** `Tests/GlanceCoreTests/HealthScoreCalculatorTests.swift`:

- 全部正常負載 → 接近 100、band `.excellent`
- 各指標於起扣/滿扣邊界值 → 預期扣分量
- 記憶體壓力 warn/critical → 額外 −5/−15
- 電池循環/健康度觸發 −2/−5
- nil 指標(無溫度、無電池)→ 該項不扣、不崩潰
- 分數夾在 0–100;`HealthBand.from(score:)` 四段邊界正確

**實機驗證**(SwiftUI view 無自動化測試,依 [[verify-by-launching-app]] 記憶):build 綠燈後實際啟動 app,確認橫幅顯示分數+顏色、下拉加寬至約 440pt、各區塊字級/圖表放大、捲動與螢幕高度上限正常、瀏海機型寬度可接受。

## 風險

- 加寬可能影響瀏海機型的下拉定位/寬度觀感 → 以實機驗證為準。
- mole CPU/記憶體「滿扣」公式可能讓單項扣分超過權重,須確認最終 clamp 後分數分佈合理(以實際讀數抽樣檢查)。
