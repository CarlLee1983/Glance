# App 解除安裝器(階段三)設計

**日期**:2026-06-16
**參考**:[tw93/mole](https://github.com/tw93/mole) 的 `uninstall`(找 App、連帶清關聯檔、安全刪除)
**前置**:[mole 借鑑路線圖],階段一(Health Score)、階段二(清理)已完成。

## 背景與目標

Glance 為 macOS 選單列工具。階段三新增 **App 解除安裝器**:移除使用者安裝的 `.app` 本體,並連帶把散落在 `~/Library` 各處的關聯檔(設定、快取、容器等)一併處理。這是含使用者資料的不可逆操作,因此安全機制與「誤檢出防止」是核心。

v1 範圍(YAGNI):列出 `/Applications` 與 `~/Applications` 直下的 `.app`,以 **Bundle ID 嚴格比對** 找出關聯檔,經「選擇→預覽→明確確認」後,把本體與關聯檔**移到垃圾桶**(`FileManager.trashItem`,可復原)。

## 設計決策(已與使用者確認)

| 項目 | 決策 |
| --- | --- |
| 對象 App 範圍 | `/Applications` + `~/Applications` 直下的 `.app`(使用者安裝;不含系統 App) |
| 刪除方式 | **移到垃圾桶**(`FileManager.trashItem`);非永久刪除 |
| 關聯檔比對 | **Bundle ID 嚴格比對**(無名稱模糊比對) |
| 執行中 App | **偵測並阻擋**(顯示「請先結束」,不代為終止) |
| 選擇粒度 | **一括**(本體 + 全部關聯檔一起;無逐檔勾選) |

## 比對規則(誤檢出防止的核心)

從 `.app/Contents/Info.plist` 取 `CFBundleIdentifier`(`bundleID`)。在既知目錄下,**僅**收符合下列其一的直接子項:

- 檔名 **完全等於** `<bundleID>`,或
- 檔名以 `<bundleID>.` **開頭**(可拾 `<bundleID>.plist`、`<bundleID>.savedState`、`<bundleID>.binarycookies` 等;但 `<bundleID>Helper` 這種無點延伸**不**拾,避免巻入別 App)。

### 探索目錄(`~/Library` 配下)

`Application Support`、`Caches`、`Preferences`、`Containers`、`Group Containers`、`Saved Application State`、`Logs`、`HTTPStorages`、`WebKit`、`Cookies`、`LaunchAgents`。

> Group Containers 的容器 ID 多為 `TEAMID.groupname`,通常不會嚴格命中 `bundleID`;**允許取不到**(寧可取漏,不可過刪)。

## 安全護欄(寫死,刪除前一律驗證)

- `.app` 本體:必須是某 apps 目錄(`/Applications`、`~/Applications`)的**直接子項**且副檔名為 `.app`,非目錄本身。
- 關聯檔:必須是某既知 `~/Library` 子目錄的**直接子項**,經 `URL.standardizedFileURL` 正規化後以該目錄為前綴(且不等於目錄本身),擋路徑遍歷(`../`)。
- 跳過符號連結。
- 無法存取/移動失敗 → 跳過並記錄(沿用 `DiskSpaceSkippedPath`),不中斷整批。
- 移除前必經「選擇 → 預覽 → 明確確認 sheet」。
- Glance 為未簽章 brew app:受 TCC 保護的子路徑落入「跳過並記錄」,不崩。

## 模組結構

純邏輯放 `GlanceCore`,UI 放 `GlanceApp`,沿用既有 `Cleanup` / `DiskSpaceAnalyzer` 的 async + 進度回呼 + skippedPaths 風格。

### GlanceCore — `Sources/GlanceCore/Uninstall/`

- `InstalledApp.swift` — 模型:`bundleID`、`name`、`bundleURL`、`sizeBytes`。`Identifiable, Sendable`。
- `AppDiscovery.swift` — async 列舉 `/Applications` + `~/Applications` 直下 `.app`;讀 `Info.plist` 的 `CFBundleIdentifier` / `CFBundleName`(缺 `CFBundleName` 退回去 `.app` 檔名),以 `CleanupSizing` 算 `sizeBytes`;**無 bundleID 者排除**。
- `RelatedFileFinder.swift` — 收 `bundleID`,掃既知 `~/Library` 子目錄,套比對規則 + 安全護欄,回傳 `[RelatedFile]`(url、sizeBytes)。
- `UninstallSafety.swift` — 純函式護欄:
  - `static func isDeletableApp(_ url: URL, within appsDirs: [URL]) -> Bool`
  - `static func isDeletableRelated(_ url: URL, within supportDirs: [URL]) -> Bool`
  - 共用「正規化前綴、非根本身、非符號連結」邏輯。
- `Uninstaller.swift` — 收 `UninstallPlan`(app + relatedFiles),逐路徑先過 `UninstallSafety` 再以**可注入的移除動作**(預設 `FileManager.trashItem`)移到垃圾桶;回傳 `UninstallRunResult`。移除動作注入化是為了單元測試 hermetic(測試注入「移到 temp 假垃圾桶」)。
- 模型:`RelatedFile`(url、sizeBytes)、`UninstallPlan`(`InstalledApp`、`[RelatedFile]`、`totalBytes`)、`UninstallRunResult`(`trashedCount`、`freedBytes`、`[DiskSpaceSkippedPath]`)。

> 執行中判定不放 GlanceCore(`NSRunningApplication` 屬 AppKit);保持 GlanceCore 專注 Foundation。

### GlanceApp — `GlanceApp/Uninstall/`

- `UninstallView.swift` — 視窗內容;單一視窗七狀態。
- `UninstallViewModel`(`@MainActor`,`ObservableObject`)— 串接 discovery/finder/uninstaller 與狀態機;**世代防護 + 相位守衛**比照 `CleanupViewModel`,丟棄過期回呼。執行中判定以 `NSRunningApplication` 比對選定 App 的 `bundleID`。
- 下拉 footer 新增「解除安裝」按鈕(`清理` 旁,`Image(systemName:"trash.slash")`)→ `openWindow(id:"uninstall")`。
- `GlanceApp.swift` 註冊 `Window("解除安裝", id:"uninstall") { UninstallView() }`。

## UI 流程(七狀態)

1. **讀取中** — 掃描 App 一覽。
2. **一覽** — 各 App 一列(名稱、大小);搜尋過濾;點選進入。
3. **計畫構建中** — 對選定 App 找關聯檔 + 執行中檢查。
4. **預覽** — `.app` 本體 + 關聯 N 件 + 合計大小清單。執行中則顯示紅色橫幅「請先結束此 App」並停用刪除鈕。
5. **確認 sheet** — 「將把 `.app` 本體 + 關聯 N 件(合計約 X)移到垃圾桶。可從垃圾桶復原。」/ 取消・解除安裝。
6. **執行中** — 進度條 + 目前處理路徑。
7. **完成** — 回收量為焦點 + 一行「移到垃圾桶 N 項 · 跳過 M 項(無權限)」+ 返回/完成。

## 測試與驗收

**單元測試(GlanceCore,用臨時目錄):**
- `AppDiscoveryTests`:temp `.app` + `Info.plist` → bundleID/name/size 正確;缺 `CFBundleName` 退回檔名;無 bundleID 者排除。
- `RelatedFileFinderTests`:命中名(`<bundleID>`、`<bundleID>.plist`)才回傳;`<bundleID>Helper` 不命中;`../` 遍歷正規化後在外 → 擋下;符號連結跳過。
- `UninstallSafetyTests`:apps 直下 `.app` → 可刪;既知目錄直下 → 可刪;範圍外路徑 → 拒;目錄本身 → 拒;符號連結 → 拒。
- `UninstallerTests`:注入「移到 temp 假垃圾桶」→ 本體與關聯都被移動、回傳實際回收量;一個範圍外惡意項目 → 被護欄擋下;移動失敗 → 進 skipped 不中斷。

**實機驗證**(依 [[verify-by-launching-app]]):build 綠後啟動 app → 先看一覽與大小是否合理 → 對一個用後即丟的測試 App 實際解除安裝一次,確認回收量、跳過顯示、執行中阻擋、垃圾桶內可見、不崩。

## 風險

- 未簽章 app 對部分關聯路徑(尤其 `Containers`、受 TCC 保護者)可能無存取權 → 落入跳過並記錄,不影響其他項。
- 移到垃圾桶可復原,降低誤刪後果;再以 Bundle ID 嚴格比對 + 寫死護欄 + 完整單元測試把關誤檢出。
- 大 App 掃描/移動耗時 → async + 進度回呼,沿用既有作法。

## 已知 fast-follow(非 v1)

- `UninstallViewModel` 無單元測試(GlanceApp 無 test target,同 `CleanupViewModel` / `DiskSpaceAnalyzerViewModel`)。
- 「對真 App 實際解除安裝一次」的破壞性驗收留給使用者親自觸發。
- 逐檔勾選、系統 App、`/Library` LaunchDaemons、名稱模糊比對、強制終止後續行 — 皆為後續可擴張項。
