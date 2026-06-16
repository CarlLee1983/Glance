# Glance

macOS 選單列主機狀態工具(類 iStat Menus)。`GlanceCore` 為純資料層,提供 CPU、記憶體、網路、磁碟、電池、感測器與 Top 程式取樣;`GlanceApp` 為常駐選單列 SwiftUI App。

除即時監看外,另借鑑 [tw93/mole](https://github.com/tw93/mole) 擴充三項維護功能(皆有單元測試與安全護欄):

- **系統健康評分** — 由現有 snapshot 計算 0–100 分,下拉頂端顯示分段橫幅
- **磁碟清理** — 掃描三類可清空目錄,預覽 → 確認 → 永久刪除
- **App 解除安裝** — 列舉已安裝 App、嚴格比對關聯檔,確認後移到垃圾桶

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

建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池/感測器 區塊(CPU/記憶體含歷史曲線與 Top 程式)。下拉內可開「設定…」:

- **登入時啟動 Glance**(`SMAppService`)
- **更新頻率**(1~5 秒)
- **選單列樣式**:圖示+數值 / 僅圖示(瀏海機型建議「僅圖示」最省寬度)
- **選單列欄位**:CPU/記憶體/網路/磁碟/電池/CPU 溫度/功耗,可勾選並拖曳調整顯示順序
- **磁碟空間分析**: 磁碟區塊可開啟唯讀分析視窗,按需掃描家目錄並列出最大資料夾與最大檔案;第一版只提供 Finder 中顯示,不刪除或移動檔案。

### 系統健康評分

下拉頂端橫幅顯示 0–100 分與分段(系統健康 ≥85 / 良好 65–84 / 普通 45–64 / 注意 <45)。評分演算法沿用 mole 的加權扣分模型:CPU(權重 30)、記憶體(25,另計記憶體壓力)、磁碟(20)、CPU 溫度(15),電池循環次數/健康度再額外微扣。純函式、無副作用,直接吃既有 `SystemSnapshot`。

### 磁碟清理

下拉可開啟清理視窗,掃描三類寫死的白名單目錄:

| 類別 | 涵蓋路徑 |
| --- | --- |
| **垃圾桶** | `~/.Trash` |
| **使用者快取與日誌** | `~/Library/Caches`、`~/Library/Logs` |
| **開發工具快取** | `~/Library/Developer/Xcode/DerivedData`、`~/.npm`、`~/.cache` |

流程為 **掃描 → 預覽勾選 → 確認 → 永久刪除**。雙重安全護欄:只允許白名單根目錄下的項目,並以正規化路徑做嚴格前綴比對、拒絕 symlink 逃逸。

> **注意**:清理為**永久刪除**(非移到垃圾桶),刪除前務必確認預覽清單。

### App 解除安裝

下拉可開啟解除安裝視窗,列舉 `/Applications` 等目錄下的 App,選定後依 bundle ID 嚴格比對散落於 `~/Library` 的關聯檔(快取、偏好設定、Application Support 等),確認後**移到垃圾桶**(可從垃圾桶還原)。

安全護欄:`.app` 與每個關聯檔都必須是某白名單目錄的**直接子項**(深度 1、嚴格前綴、拒絕 symlink);確認前會重新檢查 App 是否正在執行,執行中則阻擋。

### 感測器區塊

下拉顯示即時感測讀數:

| 欄位 | 說明 |
| --- | --- |
| **CPU 溫度** | 主值,使用私有 `IOHIDEventSystemClient` 讀取 |
| **GPU 溫度** | 可得時顯示於列表 |
| **SoC 功耗** | 以私有 `IOReport` 差值取樣(W) |
| **風扇轉速** | RPM;無風扇機型(如 MacBook Air M4)自動省略 |

### 電池進階資訊

電池區塊的副標題會自動附加可得欄位:

| 欄位 | 來源 |
| --- | --- |
| **循環次數** | `AppleSmartBattery` IORegistry |
| **健康度** | 設計電容比值(%) |
| **溫度** | 電池溫度(°C) |
| **充放電瓦數** | 即時功率(W,充電為正/放電為負) |

> **散佈方式**:溫度與功耗讀取使用私有 API(`IOHIDEventSystemClient`、`IOReport`),不符合 App Store 審查規範,因此本 App 採 **GitHub 直接散佈**,不上架 Mac App Store。

> **MacBook(瀏海機型)注意**:若選單列項目過多,新項目可能被瀏海遮蔽而看不到。可用選單列管理工具(如 Ice:`brew install --cask jordanbaird-ice`)展開隱藏項目,或接外接螢幕檢視。

## 架構

| 目錄 | 職責 |
| --- | --- |
| `Model/` | 不可變 snapshot 與原始計數型別 |
| `Sampling/` | 各指標 Sampler(差值指標注入 raw source,可單元測試) |
| `Bridge/` | 系統讀取(Mach `host_statistics` / `getifaddrs` / `statfs` / IOKit `IOPowerSources` / `libproc`) |
| `History/` | `RingBuffer` 歷史緩衝 |
| `Format/` | 人類可讀字串(百分比、位元組、速率) |
| `Health/` | 由 snapshot 算系統健康分數(純函式) |
| `Cleanup/` | 清理掃描/估算/執行與安全護欄 |
| `Uninstall/` | App 列舉、關聯檔比對、解除安裝執行與安全護欄 |

差值指標(CPU、網路、程式 CPU%)透過注入的「raw source」protocol 取得原始計數,使差值數學可在不碰真實系統的情況下單元測試;真實系統讀取集中在 `Bridge/`,由 `glance-cli` 實機驗證。清理與解除安裝的執行器把「實際刪除/移到垃圾桶」動作以閉包注入,故護欄與狀態流轉皆可在不碰真實檔案系統下測試。

## 不在 v1 範圍

公證、磁碟即時讀寫量——架構已預留,日後再加。
