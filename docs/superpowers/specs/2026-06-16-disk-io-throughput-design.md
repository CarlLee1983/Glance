# 磁碟即時讀寫量(Disk I/O Throughput)設計

**日期:** 2026-06-16
**狀態:** 已核可,待寫實作計畫

## 目標

磁碟卡片補上即時讀/寫速率(↑寫、↓讀,bytes/sec),補完監看面板目前唯一缺的常見指標。README 已將此列為「v1 範圍外、架構已預留」,本案為其落地。

## 範圍

**做:**
- 加總**全部實體磁碟**(內建 SSD + 外接 + 磁碟映像)的累計讀/寫位元組,以兩次取樣差值 ÷ 經過時間算速率。
- 磁碟卡片 body 多一行「↑寫 X/s · ↓讀 Y/s」。
- `glance-cli` 多印一行 I/O,供實機驗證。

**不做(維持最小範圍):**
- 無 I/O 歷史序列、無 sparkline 曲線。
- 無選單列(`MenuBarSegment`)欄位、不進設定。
- 不分裝置顯示,只給單一加總。

## 架構

完全鏡像現有「網路速率」差值取樣模式(注入 raw source + clock,兩次累計差值 ÷ 時間),獨立新增,不修改既有型別語意。

### 資料層(`GlanceCore`)

| 檔案 | 內容 |
| --- | --- |
| `Model/DiskIOSnapshot.swift` | `DiskIOCounters`(累計 `readBytes`/`writeBytes`:`UInt64`)、`DiskIOSnapshot`(`readBytesPerSec`/`writeBytesPerSec`:`Double`)、`DiskIOStatsSource` protocol(`func read() -> DiskIOCounters?`) |
| `Sampling/DiskIOSampler.swift` | 注入 `source` + `clock`;`sample() -> DiskIOSnapshot?`。首次取樣回速率 0;`dt ≤ 0` 回 0;以 `&-` 防 counter 環繞。寫法比照 `NetworkSampler`。 |
| `Bridge/IOBlockStorageIOSource.swift` | 公開 IOKit:`IOServiceGetMatchingServices(IOServiceMatching("IOBlockStorageDriver"))` 列舉所有實體磁碟,讀各自 `Statistics`(`kIOBlockStorageDriverStatisticsKey`)字典的 `Bytes (Read)`/`Bytes (Write)` 加總。`read()` 任一步失敗回 nil。 |

`SystemSnapshot` 新增 `diskIO: DiskIOSnapshot?`(預設參數,故障隔離 nil)。
`SystemSampler`:成員多一個 `DiskIOSampler`;`convenience init()` 接 `DiskIOSampler(source: IOBlockStorageIOSource())`;`sample()` 多取一次填入 `diskIO`。

### UI 層(`GlanceApp`)

- **`DiskSection.swift`**:新增參數 `io: DiskIOSnapshot?`。在進度條與「分析空間…」按鈕之間插一行讀/寫速率,沿用 `Formatters.rateCompact`,格式「↑寫 X/s · ↓讀 Y/s」。`io == nil` 時整行隱藏(不顯示佔位字串;I/O 為裝飾性補充,不擠壓容量主資訊)。
- **`DropdownView`**:呼叫 `DiskSection` 時多傳 `io: snapshot.diskIO`。

### CLI(`Sources/glance-cli/main.swift`)

磁碟那行下方加一行 `磁碟 I/O     ↑寫 X/s ↓讀 Y/s`。CLI 為一次性取樣,首次差值必為 0;故 CLI 改為取樣兩次、間隔約 0.5 秒,印第二次的速率以確保非零可觀察。

## 故障隔離

- `IOBlockStorageIOSource.read()` 失敗 → `DiskIOSampler.sample()` 回 nil → `SystemSnapshot.diskIO == nil` → 磁碟卡片該行隱藏、CLI 印「—」或省略。整體不崩、不影響容量顯示。

## 測試策略

- **單元測試** `DiskIOSamplerTests`(比照 `NetworkSamplerTests`):
  - 首次取樣 → 速率 0,total 正確帶出。
  - 第二次取樣 → 差值 ÷ dt 正確。
  - `dt ≤ 0`(clock 未前進)→ 回 0,不除以零。
  - counter 環繞(now < prev)→ `&-` 不崩、回合理值。
  - 維持 `GlanceCore` 既有 135 測試全綠。
- **不單測** `IOBlockStorageIOSource`(碰真實 IOKit),改由 `glance-cli` 實機印出驗證,沿用 `InterfaceCountersSource` 慣例。
- **實機**:`swift build` 綠燈;`swift run glance-cli` 在有磁碟活動時 I/O 行非零;啟動 app 目視磁碟卡片新行。

## 風險

- `IOBlockStorageDriver` 的 `Statistics` 鍵名為字串字面值(`"Bytes (Read)"` / `"Bytes (Write)"`),屬公開但非常數化的介面;以 nil 安全取值,缺鍵則該磁碟略過,不崩。
