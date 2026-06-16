# 清理功能(階段二)設計

**日期**:2026-06-16
**參考**:[tw93/mole](https://github.com/tw93/mole) 的 `lib/clean/`(dry-run、白名單、安全刪除)
**前置**:[mole 借鑑路線圖],階段一(Health Score)已完成。

## 背景與目標

Glance 原為純監控的 macOS 選單列 App。階段二讓它能**實際清理可回收空間**——這是會永久刪檔的破壞性操作,因此安全機制是核心。

v1 範圍(YAGNI,先做最大宗又相對安全的子集):清理三類可回收空間,經「掃描→預覽→勾選→明確確認」後**永久刪除**(真正釋放空間;快取本就可重生)。

非目標:瀏覽器快取、Homebrew 快取、專案殘檔(node_modules 等)、App 解除安裝(階段三)、使用者可編輯白名單(先用寫死護欄)。

## 類別與確切路徑

三個類別,**根目錄互不重疊**(避免重複計算):

| 類別 | id | 確切根路徑 | 動作 |
| --- | --- | --- | --- |
| 垃圾桶 | `trash` | `~/.Trash` | 刪根目錄底下內容物(清空) |
| 使用者快取與日誌 | `userCaches` | `~/Library/Caches`、`~/Library/Logs` | 刪根目錄底下內容物 |
| 開發工具快取 | `devCaches` | `~/Library/Developer/Xcode/DerivedData`、`~/.npm`、`~/.cache` | 刪根目錄底下內容物 |

`~/.cache` 涵蓋 uv 等;pip/CocoaPods 快取本就在 `~/Library/Caches` 下,歸 `userCaches`,不重複。

## 安全護欄(寫死,刪除前一律驗證)

- **只刪根目錄底下的內容物,永不刪根目錄本身。**
- 每個待刪路徑經 `URL.standardizedFileURL` 正規化後,必須以某個白名單根目錄為前綴(且不等於根本身),否則拒絕。可擋路徑遍歷(`../`)。
- 跳過符號連結(沿用既有掃描器作法)。
- 無法存取/刪除失敗的路徑 → 跳過並記錄原因(沿用既有 `DiskSpaceSkippedPath`),不中斷整批。
- 永久刪除前必須經過「掃描預覽 → 勾選 → 明確確認 sheet」。
- Glance 為未簽章 brew app;受 TCC 保護而無法存取的子路徑會落入「跳過並記錄」,不崩。

## 模組結構

純邏輯放 `GlanceCore`,UI 放 `GlanceApp`,沿用既有 `DiskSpaceAnalyzer` 的 async + 進度回呼 + skippedPaths 風格。

### GlanceCore — `Sources/GlanceCore/Cleanup/`

- `CleanupCategory.swift`
  ```swift
  public enum CleanupCategoryID: String, CaseIterable, Sendable { case trash, userCaches, devCaches }
  public struct CleanupCategory: Sendable {
      public let id: CleanupCategoryID
      public let displayName: String   // 垃圾桶 / 使用者快取與日誌 / 開發工具快取
      public let roots: [URL]          // 白名單根目錄(已展開 ~)
  }
  // public static func defaults(home:) -> [CleanupCategory]  ← 內建三類與路徑
  ```
- `CleanupSafety.swift` — 純函式護欄(最該獨立測):
  `static func isDeletable(_ url: URL, within roots: [URL]) -> Bool`(正規化前綴比對、非根本身、非符號連結)。
- `CleanupScanner.swift` — async 掃描各類別根目錄,算可回收 bytes + 項目數,回傳 `[CleanupCategoryResult]`;進度回呼;套用護欄(只算根目錄內、跳符號連結)。
- `CleanupExecutor.swift` — 收使用者勾選的類別,刪除其根目錄底下內容物,回傳 `CleanupRunResult`;刪除每個路徑前用 `CleanupSafety` 驗證。
- 模型:`CleanupCategoryResult`(id、reclaimableBytes、itemCount)、`CleanupRunResult`(每類 reclaimedBytes、deletedCount、`[DiskSpaceSkippedPath]`)。

### GlanceApp — `GlanceApp/Cleanup/`

- `CleanupView.swift` — 視窗內容;單一視窗五狀態:掃描中 → 勾選 → 確認 sheet → 執行中 → 完成。
- `CleanupViewModel`(`@MainActor`,`ObservableObject`)— 串接 scanner/executor 與狀態機。
- 從下拉 footer 新增「清理…」按鈕開窗(比照「設定…」開窗方式)。

## UI 流程

- **勾選**:各類別一列(名稱、路徑摘要、可回收大小、勾選框);底部顯示已選類數與總量、「清理選取…」按鈕。
- **確認 sheet**:紅色警告「將永久刪除約 X,無法復原。快取會在 App 下次使用時自動重建」+ 將清理類別與大小;「取消 / 永久刪除」。
- **執行中**:進度條 + 目前刪除路徑。
- **完成**:極簡圓環(回收量為焦點)+ 一行「刪除 N 項 · 跳過 M 項(無權限)」+「完成」。

## 測試與驗收

**單元測試(GlanceCore,用臨時目錄):**
- `CleanupSafetyTests`:根目錄底下路徑 → 可刪;根目錄本身 → 拒絕;根目錄外路徑(如 `~/Documents`)→ 拒絕;符號連結 → 拒絕;`../` 遍歷正規化後在外 → 拒絕。
- `CleanupScannerTests`:temp 假快取樹 → 各類別 bytes/項目數正確、符號連結跳過。
- `CleanupExecutorTests`:執行刪除後只刪根目錄內容物、**根目錄保留**、回傳實際回收量;無權限/失敗 → 進 skipped 不中斷;一個指向根目錄外的惡意項目 → 被護欄擋下、不被刪。

**實機驗證**(依 [[verify-by-launching-app]]):build 綠後啟動 app,先只掃描確認大小合理,再對垃圾桶實清一次,確認回收量、圓環畫面、跳過項顯示正常、不崩。

## 風險

- 未簽章 app 對部分快取路徑可能無存取權 → 落入跳過並記錄,不影響其他類別。
- 永久刪除不可逆 → 以「明確確認 sheet + 寫死護欄 + 完整單元測試」把關;v1 只開三個相對安全的類別。
- 大目錄掃描/刪除耗時 → async + 進度回呼,沿用既有掃描器作法。
