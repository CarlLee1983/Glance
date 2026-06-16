# 記憶體壓力當主角 — 設計 spec

- 日期:2026-06-16
- 範圍:記憶體下拉區塊的呈現升級(借鑑活動監視器的記憶體壓力模型)
- 不碰私有 API、不需 sudo,全靠既有取樣與歷史管線

## 目標

記憶體區塊目前只呈現「一個用量百分比 + 單色用量趨勢線」。Apple 自己強調「看記憶體壓力,不是看用量」。本案讓**壓力成為視覺主角**:

- 標題數字維持「已用 %」,但**顏色改依壓力**(綠/黃/紅)
- 副標追加「· 壓力:正常/警告/嚴重」
- 歷史 sparkline 維持「已用 %」的高度幾何,但**逐段依壓力著色**(綠→黃→紅)

配色採 macOS 活動監視器語義色:**綠=正常、黃=警告、紅=嚴重**。

## 設計決策(已與使用者確認)

1. **曲線呈現**:保留「已用 %」曲線的幾何,線色隨當下壓力分段切換(同一條線變色),非改畫壓力等級階梯圖。
2. **標題列**:數字不變(如 79%),顏色改依壓力;副標追加壓力詞;拿掉原本的容量徽章。
3. **配色**:活動監視器語義色 綠/黃/紅(非沿用現有徽章的藍/橙/紅)。
4. **離散三段**:沿用既有 `MemoryPressure.evaluate` 的三段模型,不引入連續壓力分數。
5. **門檻不動**:`evaluate` 維持 >90% 或 swap>實體一半 → critical;>75% → warning。

## 架構與元件

### 1. 資料層(GlanceCore,純函式、可單元測試)

**`MemoryPressure` 擴充**(`Sources/GlanceCore/Model/MemorySnapshot.swift`)

```swift
extension MemoryPressure {
    /// 歷史編碼與分段著色用的序數:normal=0 / warning=1 / critical=2。
    public var level: Int { … }
    /// 副標顯示字串:正常 / 警告 / 嚴重。
    public var displayLabel: String { … }
}
```

**`MetricHistory` 擴充**(`Sources/GlanceCore/History/MetricHistory.swift`)

- 新增 `public private(set) var memoryPressure: RingBuffer<Double>`,容量與其他指標相同(預設 90)。
- `init(capacity:)` 一併初始化。
- `record(_:)` 每 tick 追加 `Double(snapshot.memory?.pressure.level ?? 0)`;缺值記 0(normal),與既有 `memory` buffer 逐格對齊。

> 理由:壓力依賴 used% 與 swap,無法只從 used% 反推,故必須獨立記錄一條等長序列。

### 2. 配色單一來源(GlanceApp,SwiftUI 層)

新增 `PressureColor`(小工具,例如 `GlanceApp/Dropdown/PressureColor.swift`):

- `MemoryPressure → Color`(green / yellow / red)
- 另提供 `Int(level) → Color`,供 sparkline 由歷史序數取色。
- 標題數字顏色與 sparkline 分段色共用此來源,避免兩處重複定義。

### 3. Sparkline 分段著色(`GlanceApp/Components/Sparkline.swift`)

新增可選參數 `bandColors: [Color]? = nil`,**向後相容**(CPU/網路維持單色):

- 給定時(長度 == `values` 數),沿用現有逐段三次貝氏曲線迴圈,將原本單一 stroke 拆成**每段各自 stroke**,段色取該段兩端點中**較嚴重(色階較高)的一側**(保守:寧可早一格顯示紅)。
- 區域填色維持淡中性(不逐段變色),只有折線分段變色,視覺為「一條會變色的線」。
- `bandColors == nil` 時行為與現狀完全一致。

### 4. 卡片接線

**`MetricCard`**(`GlanceApp/Dropdown/DropdownChrome.swift`)

- 新增可選 `valueColor: Color? = nil`;為 nil 時維持現狀(primary)。其他卡片不傳即不受影響。

**`MemorySection`**(`GlanceApp/Dropdown/MemorySection.swift`)

- `value` 維持 `Formatters.percent(usedFraction)`,新增 `valueColor: PressureColor(pressure)`。
- `status: nil`(移除容量徽章)。
- `detail` 追加「· 壓力:\(pressure.displayLabel)」。
- Sparkline 傳入 `bandColors`(由壓力歷史序數映射)。
- 需要新的輸入:壓力歷史序列。

**`DropdownView`**(`GlanceApp/Dropdown/DropdownView.swift`)

- 多餵一條 `history.memoryPressure.values`(或映射後的 `[Color]`/`[MemoryPressure]`)給 `MemorySection`,與既有 `history.memory.values` 等長。

## 呈現(示意)

```
記憶體         79%   ← 黃(警告)
12.6 / 16.0 GB · 壓力:警告
〰〰 綠→黃→紅 隨壓力變的曲線 〰〰
```

## 測試 / 驗證

- **單元測試**
  - `MetricHistoryTests`:壓力記錄逐格對齊既有指標、缺值記 0、容量上限行為。
  - `MemoryPressureTests`:`level` 與 `displayLabel` 三狀態映射。
- **視覺驗證**(View 程式不單元測試,照專案慣例實際啟動 app)
  - 壓力低時 sparkline 與數字全綠;人為灌記憶體壓力時轉黃/紅;副標文字隨之變動。

## 不在範圍

- 不存連續「壓力分數」(維持離散三段)。
- 不動 `MemoryPressure.evaluate` 門檻。
- 不提供記憶體釋放/purge 動作(先前評估在 Apple Silicon 上實益低且與安全護欄哲學衝突)。
- 不新增「可用記憶體 Available / 用量拆解」(屬另一獨立提案,本案不含)。
