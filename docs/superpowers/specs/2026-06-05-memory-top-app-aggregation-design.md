# 記憶體監控按 App 彙總 — 設計文件

**日期:** 2026-06-05
**狀態:** 已確認,待實作

## 目標

讓 Glance 的記憶體監控明確表達「哪個 app 佔用記憶體最大」。目前下拉視窗的記憶體區塊列出前 3 名**單一行程**(依 `ri_phys_footprint` 排序),但像 Chrome、Safari、Xcode 會開很多 helper 子行程,記憶體被拆散在多個 entry,使第一名常常只是某個 helper,而非整個 app 的總用量。

本功能把記憶體排行改為**按 app 彙總**:把同一 app 的所有行程(含 helper)記憶體加總,讓第一名反映整個 app 的真實用量,並在 UI 上明顯凸顯第一名。

**範圍:** 只套用於記憶體。CPU 區塊的 top 程式清單維持現狀(單行程、依 CPU 排序)。

## 非目標

- 不彙總 CPU 清單。
- 不另開獨立視窗(沿用既有下拉視窗記憶體區塊)。
- 不使用私有 API(如 `responsibility_get_pid_for_pid`),避免啟動閃退與系統更新相容風險。
- 不顯示每個 app 底下子行程的展開明細(第一版只給彙總值與 processCount)。

## 架構

維持既有邊界原則:彙總與歸類邏輯放在 `GlanceCore`(純公開 API、可單元測試、不依賴 AppKit);app 圖示等呈現留在 `GlanceApp`。

### 1. 核心彙總邏輯(GlanceCore)

**取得執行檔路徑**

`RawProcess` 新增 `executablePath: String?` 欄位。`LibprocSource` 用公開 API `proc_pidpath(pid:)` 填入。對受保護系統行程可能回傳空字串 → 視為 `nil`。

**App 歸類(純函式,可測試)**

新增 `Sources/GlanceCore/Sampling/AppGrouping.swift`,提供把執行檔路徑映射成 app 身分的純函式:

- 在路徑中找**最後一個 `.app` 路徑元件**:
  - `bundleURL` = 到該 `.app` 元件為止的路徑
  - `appName` = 該元件去掉 `.app` 副檔名
  - `groupKey` = bundle 路徑
  - 例:`/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/.../Google Chrome Helper (Renderer)` → appName「Google Chrome」、bundleURL 指向 `/Applications/Google Chrome.app`
- 找不到 `.app`(daemon / CLI,或 `executablePath` 為 `nil`):
  - `appName` = 行程名(`RawProcess.name`)
  - `bundleURL` = `nil`
  - `groupKey` = 行程名
- 純字串運算,不碰檔案系統,易於單元測試。

**彙總模型**

新增 `Sources/GlanceCore/Model/AppMemoryUsage.swift`:

```swift
public struct AppMemoryUsage: Equatable, Identifiable {
    public let id: String          // 群組鍵(bundle 路徑或行程名)
    public let appName: String
    public let bundleURL: URL?     // 給 app 層抓圖示;非 app 為 nil
    public let memoryBytes: UInt64 // 同 app 所有行程 phys_footprint 加總
    public let processCount: Int   // 合併了幾個行程
}
```

**彙總排序**

`ProcessSampler.sample()` 改回傳 `(topCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage])`:

- CPU 路徑不變(單行程、依 cpuFraction 排序、取前 N)。
- 記憶體路徑:用 `AppGrouping` 把每個行程歸到 app 鍵 → 依鍵分組 → `memoryBytes` 加總、`processCount` 計數 → 由大到小排序(同值以 appName 穩定排序)→ 取前 `limit`。
- 移除原本的 per-process `topMemory`,避免死碼。

### 2. 資料流串接(GlanceCore)

- `SystemSnapshot.topByMemory: [ProcessUsage]` → 改為 `topMemoryApps: [AppMemoryUsage]`。
- `SystemSampler.sample()` 接上彙總結果。
- 更新所有引用舊欄位的程式與測試(`SystemSamplerTests`、`MetricsStoreTests`、`ProcessSamplerCombinedTests`、`MenuBarTextTests`、`MetricHistoryTests` 等視實際引用而定)。

### 3. UI 呈現(GlanceApp)

- `MemorySection` 改吃 `topApps: [AppMemoryUsage]`。
- 新增 `GlanceApp/Components/AppMemoryList.swift`:
  - **第一名凸顯**:較大的列、左側 app 圖示(`NSWorkspace.shared.icon(forFile: bundleURL.path)`;`bundleURL` 為 `nil` 時用泛用 `memorychip`/`app` 圖示)、app 名加粗、加上「最佔用」標籤、記憶體用量。
  - 第 2、3 名:較小的一般列,沿用現有相對長度 bar 風格(以第一名為比例基準)。
  - 空清單沿用「暫無高記憶體程式」提示。
- CPU 區塊與 `TopProcessList` 完全不動。
- `DropdownView` 傳 `s?.topMemoryApps ?? []`。

> 圖示相關的 NSWorkspace/AppKit 只在 app 層使用,`GlanceCore` 維持不依賴 AppKit,與磁碟分析器邊界原則一致。

## 資料流

```
LibprocSource.read()            // 每行程加 executablePath
  → [RawProcess]
ProcessSampler.sample()
  → topCPU: [ProcessUsage]              (單行程,不變)
  → topMemoryApps: [AppMemoryUsage]     (AppGrouping 歸類 + 加總 + 排序)
SystemSampler.sample()
  → SystemSnapshot.topMemoryApps
DropdownView → MemorySection(topApps:) → AppMemoryList
  → 第一名凸顯(圖示由 bundleURL 經 NSWorkspace 取得)
```

## 錯誤處理

- `proc_pidpath` 失敗/空 → `executablePath = nil` → 該行程以行程名歸類,不中斷取樣。
- `source.read()` 回傳 `nil` → 沿用現有行為,回傳空清單。
- `bundleURL` 為 `nil` 或圖示取得失敗 → UI fallback 泛用圖示。

## 測試策略

- `AppGroupingTests`(GlanceCore):
  - Chrome helper 巢狀 `.app` 路徑 → 「Google Chrome」、bundleURL 正確
  - 單純 `/Applications/Foo.app/Contents/MacOS/Foo` → 「Foo」
  - 路徑含多個 `.app`(巢狀)→ 取最後一個
  - 無 `.app` 的 daemon 路徑(如 `/usr/sbin/cfprefsd`)→ 用行程名、bundleURL nil
  - `executablePath` 為 nil → 用行程名
- `ProcessSampler` 彙總測試:餵入帶 `executablePath` 的假 `RawProcess`,驗證同 app 加總、`processCount`、由大到小排序、取前 N、CPU 路徑不受影響。
- 更新引用舊 `topByMemory` 的既有測試。
- 全套件 `swift test` 與 `xcodebuild` 綠燈;啟動 app 實際驗證(記憶體區塊第一名為彙總 app、圖示正確、不閃退)。

## 風險與取捨

- 純公開 API(`proc_pidpath`),無私有 API 閃退風險。
- 「最後一個 `.app`」規則對絕大多數標準 GUI app 正確;少數非標準打包者 fallback 到行程名(可接受)。
- 受保護系統行程 `proc_pidpath` 可能回空 → fallback 行程名歸類。
