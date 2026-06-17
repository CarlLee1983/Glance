# 記憶體區「結束高佔用 App」功能設計

- 日期:2026-06-17
- 狀態:設計定案,待寫實作計畫
- 分支:`feat/memory-app-terminate`

## 背景與動機

使用者詢問「能否透過 mole 或其他工具優化儀錶板的記憶體部分」。

技術判斷:macOS 上「釋放記憶體」(mole `optimize` 內部的 `sudo purge`、釋放 inactive memory)多半是**安慰劑甚至反效果** —— inactive/cached 記憶體是隨時可回收的磁碟快取,主動清掉反而逼系統重新從 SSD 讀回,短期更慢;且需 sudo,對監控型選單列 App 是過重權限。Apple 自身把 `purge` 定位為開發/測試工具,非日常優化。

因此**不做**「釋放記憶體」按鈕。改採對使用者真正有用、且零系統傷害的方向:**揪出吃記憶體的元凶並提供引導動作**。

現況:儀錶板記憶體卡片**已有**「高記憶體應用排行」(`GlanceApp/Components/AppMemoryList.swift`,前 5 名可展開),已完成「揪元凶」的顯示。缺的是「引導/動作」—— 讓使用者能對某個高佔用 App 直接採取行動。

本功能補上這個缺口:在排行列表中,對 `.app` 類型的 App 提供**優雅結束 (graceful terminate)** 動作。

## 範圍

### 目標(v1)

- 在 `AppMemoryList` 每一列(屬於 `.app` bundle 者)提供「結束」動作。
- 動作為 **graceful terminate**(`NSRunningApplication.terminate()`):送關閉訊號,App 有機會跳「是否儲存」對話框。不需 sudo。
- 點「結束」前以**輕量 `NSAlert`** 確認,防誤點。
- 結束後依賴既有取樣週期自然刷新列表,不需手動刷新邏輯。

### 非目標(v1 刻意排除)

- 「釋放記憶體 / purge」按鈕(技術上有害,明確不做)。
- force quit / `SIGKILL`(可能丟未存資料)。
- 結束非 `.app` 的 CLI 行程(`id = "pid:..."` 類 entry,不在 `NSRunningApplication` 範圍)。
- 批次結束、結束後 toast 回饋、完整確認 sheet。
- shell out 呼叫 mole 或外部工具。

## 核心機制:可結束性與比對

### 為什麼能對應回 running app

`AppMemoryUsage`(`Sources/GlanceCore/Model/AppMemoryUsage.swift`)在聚合時已丟失原始 pid,只保留:`id`、`appName`、`bundleURL`(`.app` 才有,否則 nil)、`memoryBytes`、`processCount`。

關鍵:`NSRunningApplication` 本身有 `bundleURL` 屬性。因此對 `.app` 類 entry,可用 **`bundleURL` 比對**從 `NSWorkspace.shared.runningApplications` 找回對應的 running app,無需 pid,也無需反推 bundle ID。

### 可結束條件

一個 `AppMemoryUsage` entry 可結束,當且僅當:

1. `bundleURL != nil`(屬於 `.app` bundle),且
2. `NSWorkspace.shared.runningApplications` 中存在 `bundleURL` 標準化後相符的 app,且
3. 該 app **不是 Glance 自身**。

不符者:不顯示結束鈕,維持純顯示(現狀)。

### 結束行為

找出所有 `bundleURL` 相符的 `NSRunningApplication`(同一 App 可能多實例),逐一呼叫 `.terminate()`(graceful)。任一實例失敗不中斷其他。

## 架構與分層

沿用既有 GlanceCore(純邏輯,可測)/ GlanceApp(AppKit 副作用,薄)分層,並仿照 `Uninstaller`「移除動作可注入」的 hermetic 測試模式。

### GlanceCore(純、可測):`AppTerminationMatcher`

純函式,不碰 AppKit:

- 輸入:目標 `bundleURL`,加上一組 running app 的輕量描述(每個含 `bundleURL`、`isCurrentApp` 旗標)。
- 輸出:該結束哪些(回傳相符且非自身的描述子集)。
- 標準化比對 bundleURL(`standardizedFileURL` / resolve symlink,避免路徑表示差異漏比對)。

對應的輕量描述型別(例 `RunningAppRef`)亦定義在 GlanceCore,讓 matcher 與 AppKit 解耦、可單元測試。

### GlanceApp(副作用,薄):`AppTerminator`

- 把 `NSWorkspace.shared.runningApplications` 映射成 `RunningAppRef`(帶 `isCurrentApp = ($0 == NSRunningApplication.current)`),連同目標 entry 的 `bundleURL` 餵給 `AppTerminationMatcher`。
- 對 matcher 回傳的每個結果,找回對應 `NSRunningApplication` 並呼叫終止動作。
- **終止動作以 closure 注入**(預設 `{ $0.terminate() }`),以利測試替身。
- 回傳簡單結果(嘗試結束的數量 / 是否找到相符),供 UI 決定是否需要任何回饋。

## 資料流

1. 使用者 hover `AppMemoryList` 某列 → 若該 entry 可結束,右側淡入小「結束」鈕。
2. 點「結束」→ 輕量 `NSAlert`:標題「確定要結束「<appName>」嗎?」、訊息「未儲存的資料可能遺失。」、按鈕 [取消] [結束]。
3. 確認 → 呼叫 `AppTerminator`,對相符的 running app(s) `terminate()`。
4. App graceful 結束(可能自行跳儲存對話框)→ 下一取樣週期該列自然消失/更新。

## 錯誤處理與邊界

- **競態(按下時 App 已自行退出)**:`runningApplications` 找不到相符 → 靜默 no-op,不報錯。
- **多實例**:同 bundleURL 多個 running app → 全部 terminate。
- **排除自身**:matcher 以 `isCurrentApp` 過濾,UI 也不對 Glance 的 bundleURL 顯示結束鈕(雙重保險)。
- **terminate() 回傳 false**(罕見,App 拒絕 graceful 結束):v1 不升級為 force quit,靜默接受。
- **非 .app entry**:無 `bundleURL`,可結束條件即不成立,不顯示鈕。

## 測試策略

- `AppTerminationMatcherTests`(GlanceCore,新增):
  - 目標 bundleURL 有相符 running app → 回傳該 app。
  - 目標相符但為自身(`isCurrentApp`)→ 排除。
  - 無相符 → 回傳空。
  - 多實例相符 → 全部回傳。
  - bundleURL 路徑表示差異(symlink / 尾斜線)仍能比對。
- `AppTerminator`:GlanceApp 無 test target(同 `CleanupViewModel`/`UninstallViewModel` 既有取捨),其邏輯已盡量下推至可測的 matcher;注入式終止 closure 讓核心可在不真正殺 App 下驗證。
- **破壞性實機驗收**(真的結束一個 App 一次)留給使用者親自觸發(比照 cleanup/uninstall 慣例)。

## 受影響檔案(預估)

| 動作 | 檔案 | 說明 |
|------|------|------|
| 新增 | `Sources/GlanceCore/Process/AppTerminationMatcher.swift` | 純比對邏輯 + `RunningAppRef` 型別 |
| 新增 | `Tests/GlanceCoreTests/AppTerminationMatcherTests.swift` | matcher 單元測試 |
| 新增 | `GlanceApp/Components/AppTerminator.swift` | AppKit 副作用薄層,注入式 terminate |
| 修改 | `GlanceApp/Components/AppMemoryList.swift` | hover 結束鈕 + 確認 alert + 串接 `AppTerminator` |

(實際路徑/檔名以實作計畫為準。)

## 開放問題

無。設計已定案。
