# 設計文件:改善「分析空間」(磁碟空間分析)

- 日期:2026-06-17
- 狀態:已通過腦力激盪,待實作計畫
- 範圍:重寫 `DiskSpaceAnalyzer` 為樹狀模型、加入快取、互動刪除(移到垃圾桶)、Bento UI 升級

## 1. 背景與目標

現有「分析空間」(`DiskSpaceAnalyzer`)是唯讀工具:遞迴掃描家目錄、列出最大的前 50 個資料夾/檔案的平面排行榜,只能在 Finder 顯示,無法下鑽,也不能直接動手清理。每次開啟都重新整棵掃描,無快取。

本次升級涵蓋四個方向(使用者全選):**功能更強、UI/UX 升級、效能與快取、互動操作**。

### 已確認的核心決策

| 決策點 | 結論 |
|--------|------|
| 瀏覽模型 | **樹狀下鑽(B)為骨架**,每層用**佔比長條(A)**呈現 |
| 圖示 | 一律用 SF Symbols,**不使用 emoji** |
| 處理方式 | 選取項目**移到垃圾桶**(`FileManager.trashItem`,可在 Finder 還原) |
| 掃描範圍 | **家目錄為預設 + 可選擇其他資料夾** |
| 運作模式 | **一次並行掃完建樹 + 快取**,之後下鑽瞬間完成、再次開啟讀快取秒開 |

## 2. 架構總覽

```
GlanceCore (邏輯層)
├── Model/DiskNode.swift            # 樹狀節點 + 長尾聚合(新)
├── Sampling/DiskSpaceAnalyzer.swift # 改寫:TaskGroup 並行建樹
├── Store/DiskScanCache.swift       # Codable 樹快取(新)
└── Uninstall/DiskTrashSafety.swift # 任意深度刪除護欄(新)

GlanceApp (UI 層)
└── DiskAnalyzer/
    ├── DiskSpaceAnalyzerWindow.swift     # 改寫
    ├── DiskSpaceAnalyzerViewModel.swift  # 改寫
    └── Components/
        ├── BreadcrumbBar.swift     # 麵包屑(新)
        ├── DiskNodeRow.swift       # 清單列(新)
        ├── ScanSummaryStrip.swift  # Bento 摘要列(新)
        └── TrashActionBar.swift    # 底部刪除列(新)
```

資料流:`DiskSpaceAnalyzer`(並行建樹 + 進度回呼)→ ViewModel(`@MainActor`,持有整棵樹 + 導覽狀態)→ `@Published` → View 重繪。快取在掃完後寫入、開啟時讀取。

## 3. 核心引擎與資料模型

### DiskNode(取代平面 top-50 清單)

```swift
public struct DiskNode: Identifiable, Sendable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: DiskSpaceItemKind   // .folder / .file
    public let sizeBytes: UInt64         // 整棵子樹總大小
    public let modifiedAt: Date?
    public let children: [DiskNode]      // 依大小遞減排序;檔案為空陣列
    public let isAggregate: Bool         // true = 「其他 N 個項目」合成節點
    public let aggregateCount: Int       // 合成節點包含的項目數(否則 0)
}
```

value type、遞迴結構,天然 `Sendable` + `Codable`(快取用)。

### 掃描引擎改寫(`DiskSpaceAnalyzer`)

- 用 `TaskGroup` 並行掃描頂層子目錄,各自遞迴 → 由下往上彙總出整棵 `DiskNode`
- 每層 children 依 `sizeBytes` 遞減排序
- **長尾聚合**:每個資料夾只保留較大的前 N 個(預設 N 約 100,可調)個別項目,其餘合併成單一「其他 M 個項目」合成節點(`isAggregate = true`,只記總和與計數、`children` 為空、不可下鑽、不可選取)。同時解決:
  - 記憶體:避免 `node_modules` 等海量小檔塞爆記憶體與快取檔
  - UI:避免單一資料夾渲染數千列
- 保留現有安全處理:symlink 偵測跳過、權限/不存在路徑跳過、每層檢查 `Task.isCancelled`
- 進度回呼:沿用節流(0.2 秒或每 100 項),回報 `scannedCount` / `skippedCount` / `currentPath`

### 快取(`Store/DiskScanCache.swift`)

- 掃完把整棵 `DiskNode` 以 `Codable`(JSON 或 plist)序列化到 Application Support,key = 正規化後的 root 路徑
- 再次開啟同一 root:直接載入快取秒開,標頭顯示「上次掃描於 …(時間戳)」+「重新掃描」按鈕
- 失效時機:使用者按重新掃描、或執行刪除後更新該樹(見 §5)

## 4. UI / UX(Bento 風格,延續 Cleanup / Uninstall)

視窗由上到下:

1. **標頭**:標題「磁碟空間分析」+ root 路徑 +「上次掃描於 …」狀態;右側「選擇資料夾…」「重新掃描 / 取消」按鈕
2. **Bento 摘要列**(4 格):目前資料夾大小 / 項目數 / 已選取(N 項·大小,紅色強調)/ 磁碟可用
3. **麵包屑**:`~ › Library › Caches`,可點任一層跳回該層
4. **清單**:目前資料夾的 children 依大小遞減。每列 = 勾選框 + SF Symbols 圖示(資料夾/檔案依型別)+ 名稱 + 佔比長條(寬度 = 該項大小 / 父資料夾總大小,故同層各列加總約滿格)+ 大小 + 修改日 + 下鑽 chevron(資料夾才有)+ Finder 顯示鈕
   - 長尾收合列「其他 N 個小項目」:不可下鑽、不可選取、樣式弱化
5. **底部刪除列**(`TrashActionBar`):有勾選才出現,顯示「已選取 N 項,共 X GB — 將移到垃圾桶(可在 Finder 還原)」+「移到垃圾桶」按鈕;無勾選時顯示唯讀提示
6. 深色模式一併套用,與既有視窗一致

**掃描中**:顯示進度(已掃描數、目前路徑)與「取消」;掃完後呈現樹。

**導覽互動**:點資料夾名稱或 chevron → 下鑽;點麵包屑 → 跳層;Finder 鈕 → `NSWorkspace` 顯示。

## 5. 刪除安全護欄與執行

### DiskTrashSafety(任意深度,異於 UninstallSafety 的 depth-1)

`isDeletable(_ url:, withinRoot:)` 一律比照「移到垃圾桶」,需同時滿足:

1. **必須是掃描 root 的子孫**:正規化後 root 為嚴格前綴、元件數 > root 元件數(不能刪未掃描範圍)
2. **不得等於 root 或其祖先**:避免一鍵丟掉整個掃描根
3. **拒絕 symlink 葉節點**:沿用 `standardizedFileURL` + `isSymbolicLinkKey` 偵測(不解析最後一段 symlink)
4. **保護清單**:即使位於 root 之下,仍硬擋若干關鍵頂層目錄整包刪除(如 `~/Library`、`~/.ssh`、`~/Documents`),避免大範圍誤刪
5. 防呆:拒絕過淺的 root(如 `/`)

### 執行流程

- 按「移到垃圾桶」→ 確認對話框列出項目數與總大小 → 對每個通過 `DiskTrashSafety` 的項目呼叫 `FileManager.trashItem`
- 任一項失敗不中斷其餘項,結束後回報成功/失敗計數
- 刪除後:從記憶體樹移除對應節點、沿麵包屑往上重算各層 `sizeBytes`、更新快取(不必整棵重掃)

## 6. 測試規劃(TDD,延續 GlanceCoreTests 風格)

**核心層:**
- 樹建構:子樹大小正確彙總到各層、children 依大小遞減
- 長尾聚合:大量小項目正確收合成「其他 N 個」合成節點(總和、計數正確),大項目仍個別保留
- 取消:`Task.isCancelled` 回傳 cancelled 狀態
- 快取往返:`Codable` encode → decode 後樹一致
- `DiskTrashSafety`:正常子孫可刪;root 本身/祖先/範圍外/symlink 葉/保護清單一律拒絕;過淺 root 拒絕

**ViewModel 層(`@MainActor`):**
- 下鑽更新麵包屑與 currentNode、點麵包屑跳層、回上層
- 勾選切換與已選取總大小計算
- 刪除後節點移除 + 祖先大小重算 + 快取標記更新

## 7. 不在本次範圍(YAGNI)

- Treemap 方塊圖視覺化(僅作為未來選項)
- 整碟/多根掃描(目前家目錄 + 可選資料夾已足夠)
- 跨掃描的歷史趨勢比較
- 快取自動過期/背景重掃(改由使用者手動「重新掃描」)
