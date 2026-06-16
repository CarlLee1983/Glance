# 磁碟 I/O 歷史曲線 + 選單列欄位設計

**日期:** 2026-06-16
**狀態:** 已核可,待寫實作計畫

## 目標

把磁碟即時讀/寫量補完到與 CPU/記憶體/網路一致的呈現:

1. **下拉磁碟卡片** 加歷史曲線(疊圖雙線:寫=實色、讀=淡色)。
2. **選單列** 新增可勾選的「磁碟讀寫」欄位(只顯示寫入速率,鏡像網路欄位)。

磁碟 I/O 的取樣層(`DiskIOSampler` + `IOBlockStorageIOSource` + `SystemSnapshot.diskIO`)已於前案落地,本案僅補「歷史緩衝」與「呈現」兩塊,讓 I/O 與其他指標的顯示模式對齊。

## 範圍

**做:**
- `MetricHistory` 加 `diskRead`/`diskWrite` 兩條 `RingBuffer<Double>`。
- 磁碟卡片插入疊圖雙線 sparkline(讀寫共用同一 Y 尺度)。
- `MenuBarSegment` 新增 `diskIO` 欄位(只顯示寫入速率),可在設定勾選並拖曳排序。

**不做(維持最小範圍):**
- 不動取樣層(`DiskIOSampler`/`IOBlockStorageIOSource` 已落地)。
- 不改容量主資訊與既有「↑寫 X/s · ↓讀 Y/s」文字行(兩者保留)。
- 不加新設定開關(沿用既有 `menuBarSegments` 欄位勾選機制)。
- `Sparkline` 元件零修改(以 ZStack 疊兩個實例 + 共用 `maxValue` 達成雙線)。
- 選單列欄位不顯示讀取或讀+寫並列(省寬度,顧及瀏海機型)。

## 架構

完全鏡像既有「網路歷史曲線 + 網路選單列欄位」模式:歷史進 `MetricHistory` 的 `RingBuffer`,選單列進 `MenuBarSegment`/`MenuBarText`,UI 用既有 `Sparkline`。資料層改動由編譯器窮舉 switch 強制補齊,故障隔離沿用既有 optional 設計。

### 資料層(`GlanceCore`)— 歷史緩衝

`DiskIOSnapshot`(含 `readBytesPerSec`/`writeBytesPerSec`)已存在,**不需新型別**。

`Sources/GlanceCore/History/MetricHistory.swift`:

```swift
public private(set) var diskRead: RingBuffer<Double>
public private(set) var diskWrite: RingBuffer<Double>

// init(capacity:)
diskRead = RingBuffer(capacity: capacity)
diskWrite = RingBuffer(capacity: capacity)

// record(_:):缺值記 0,鏡像 netDown/netUp
diskRead.append(snapshot.diskIO?.readBytesPerSec ?? 0)
diskWrite.append(snapshot.diskIO?.writeBytesPerSec ?? 0)
```

沿用既有 90 容量,與其他指標同步推進。

### 選單列欄位(`GlanceCore` + `GlanceApp`)

`Sources/GlanceCore/MenuBar/`:
- `MenuBarSegment` 列舉新增 `case diskIO`(放在 `disk` 之後)。
- `MenuBarText.readings` 補 `.diskIO` 分支:有 `snapshot.diskIO` 時輸出
  `SegmentReading(segment: .diskIO, value: Formatters.rateCompact(io.writeBytesPerSec), status: .normal)`;
  `diskIO == nil` 時該筆略過(鏡像網路欄位作法)。

`GlanceApp/`(兩處窮舉 switch,編譯器強制補齊):
- `MenuBar/MenuBarSegmentIcon.swift`:`.diskIO → "arrow.up"`(寫入向上,與磁碟容量 `internaldrive` 區隔)。
- `Settings/SettingsView.swift` 的 `label(_:)`:`.diskIO → "磁碟讀寫"`。

預設仍不勾選(`menuBarSegments` 預設 `cpu,memory,network`)。勾選與拖曳排序由既有機制自動支援。

### UI 層(`GlanceApp`)— 雙線曲線

`GlanceApp/Dropdown/DiskSection.swift` 新增參數 `readHistory: [Double]`、`writeHistory: [Double]`。在容量進度條與既有讀寫文字行之後、「分析空間…」按鈕之前,插入疊圖雙線曲線:

```swift
let ioMax = max(readHistory.max() ?? 0, writeHistory.max() ?? 0, 1)
ZStack {
    Sparkline(values: readHistory,  maxValue: ioMax, color: .yellow.opacity(0.45)) // 讀=淡
    Sparkline(values: writeHistory, maxValue: ioMax, color: .yellow)               // 寫=實
}
.frame(height: 52)
.clipShape(RoundedRectangle(cornerRadius: 6))
```

- **共用 `ioMax`** 讓兩線同尺度可比;`Sparkline` 零修改。
- 全為 0(剛啟動/取樣失敗)時 `ioMax = 1`,兩線貼底,無除零。

`GlanceApp/Dropdown/DropdownView.swift`:呼叫 `DiskSection` 時多傳
`readHistory: store.history.diskRead.values`、`writeHistory: store.history.diskWrite.values`
(鏡像 `downHistory` 的傳法)。

既有「↑寫 X/s · ↓讀 Y/s」文字行保留,與曲線並存(文字給精確值、曲線給趨勢)。

## 資料流

`SystemSampler.sample()` → `SystemSnapshot.diskIO`(已落地)
→ `MetricsStore.apply()` 同時 `snapshot = snap` 與 `history.record(snap)`(`diskRead`/`diskWrite` 各推一筆)
→ SwiftUI 觀察:`DiskSection` 讀 `store.history.diskRead/diskWrite.values` 畫雙線;`MenuBarText.readings` 讀 `snapshot.diskIO` 出選單列寫入速率。

## 錯誤處理與故障隔離

`diskIO` 本就 optional:
- 歷史:nil 記 0,曲線連續貼底,不中斷其他指標。
- 選單列:nil 時 `.diskIO` 該筆略過,不影響其他欄位。
- 全 0 時 `ioMax = 1` 防除零。

## 測試

- **`MetricHistoryTests`**:`record` 後 `diskRead`/`diskWrite` 末值等於 snapshot 的讀/寫速率;`diskIO == nil` 時記 0。
- **`MenuBarTextTests`**:勾選 `.diskIO` 時讀數值為寫入速率的 `rateCompact`、status `.normal`;`diskIO == nil` 時該筆略過。
- **GlanceApp UI**(`DiskSection`/`DropdownView`):無 test target,沿用既有慣例不寫單元測試,靠 `glance-cli` 與實機目視驗收(啟動 app 確認雙線與選單列欄位)。

## 非目標

- 選單列顯示讀取或讀+寫並列。
- 為 I/O 曲線新增獨立設定開關。
- 修改 `Sparkline` 元件或取樣層。
