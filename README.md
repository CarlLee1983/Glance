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
