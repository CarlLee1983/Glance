# Glance

macOS 選單列主機狀態工具(類 iStat Menus)。本套件 `GlanceCore` 為純資料層,提供 CPU、記憶體、網路、磁碟、電池與 Top 程式取樣;選單列 UI 於後續 GlanceApp 計畫實作。

## 需求

- macOS 13+(Apple Silicon)
- Swift 5.9+

## 使用

```bash
swift test           # 執行單元測試
swift run glance-cli # 一次性印出目前主機狀態
```

`glance-cli` 輸出範例:

```
=== Glance ===
CPU        25%
記憶體        12.6 GB / 16.0 GB (79%)
網路         ↓19.6K ↑118.7K
磁碟         328.9 GB / 460.4 GB (71%)
電池         99%

-- Top CPU --
  2%	WindowServer
  ...
```

## 選單列 App(GlanceApp)

需先安裝 XcodeGen(`brew install xcodegen`),再:

    xcodegen generate          # 由 project.yml 產生 Glance.xcodeproj
    xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build

建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池 區塊(CPU/記憶體含歷史曲線與 Top 程式)。下拉內可開「設定…」:

- **登入時啟動 Glance**(`SMAppService`)
- **更新頻率**(1~5 秒)
- **選單列樣式**:圖示+數值 / 僅圖示(瀏海機型建議「僅圖示」最省寬度)
- **選單列欄位**:CPU/記憶體/網路/磁碟/電池,可勾選並拖曳調整顯示順序

> **MacBook(瀏海機型)注意**:若選單列項目過多,新項目可能被瀏海遮蔽而看不到。可用選單列管理工具(如 Ice:`brew install --cask jordanbaird-ice`)展開隱藏項目,或接外接螢幕檢視。

## 架構

| 目錄 | 職責 |
| --- | --- |
| `Model/` | 不可變 snapshot 與原始計數型別 |
| `Sampling/` | 各指標 Sampler(差值指標注入 raw source,可單元測試) |
| `Bridge/` | 系統讀取(Mach `host_statistics` / `getifaddrs` / `statfs` / IOKit `IOPowerSources` / `libproc`) |
| `History/` | `RingBuffer` 歷史緩衝 |
| `Format/` | 人類可讀字串(百分比、位元組、速率) |

差值指標(CPU、網路、程式 CPU%)透過注入的「raw source」protocol 取得原始計數,使差值數學可在不碰真實系統的情況下單元測試;真實系統讀取集中在 `Bridge/`,由 `glance-cli` 實機驗證。

## 不在 v1 範圍

溫度/風扇(Apple Silicon 需 IOKit SMC 私有讀取)、登入時啟動、公證、磁碟即時讀寫量——架構已預留,日後再加。
