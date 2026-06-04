# Glance 狀態圖示選單列模式 — 設計文件

- 日期: 2026-06-04
- 範圍: 改善目前「僅圖示」模式,讓圖示本身能表達各指標狀態
- 不在範圍: 新增網路門檻設定、通知中心告警、下拉頁重設計、溫度/風扇

## 背景與目標

目前 `MenuBarDisplayMode.iconOnly` 只顯示 SF Symbol 圖示。它能節省選單列寬度,但幾乎沒有資訊價值:使用者只能知道哪些欄位正在顯示,無法從選單列直接判斷 CPU、記憶體、磁碟或電池是否異常。

本次改善採用「彩色多圖示狀態列」方向:

- 已選欄位仍依設定順序顯示。
- 每個圖示依該指標目前狀態套色。
- 正常時仍保持極簡;異常時不必展開文字也能知道是哪個指標需要注意。

成功標準:

- 「僅圖示」不再只是裝飾,而是能表達正常、偏高、注意、充電中等狀態。
- 既有使用者的 `menuBarDisplayMode = iconOnly` 設定不失效。
- 狀態判斷留在 `GlanceCore`,App 層只負責圖示與顏色呈現。

## 使用者體驗

設定頁中把顯示文字從「僅圖示」改為「狀態圖示」。底層 raw value 保留 `iconOnly`,避免破壞既有 `UserDefaults`。

`圖示 + 數值` 模式維持目前行為:顯示每個已選欄位的圖示與短數值。此模式先不強制套狀態色,避免在有多個數字時過度搶眼。

`狀態圖示` 模式顯示每個已選欄位的圖示,不顯示數值:

- `normal`: 次要灰色
- `elevated`: 橘色
- `critical`: 紅色
- `charging`: 綠色或系統 accent

若 snapshot 尚未產生或所有欄位缺資料,仍顯示 `—`。

## 狀態規則

沿用既有 `MetricStatus` 門檻,避免為選單列另建一套狀態語意:

- CPU: `MetricStatus.load(cpu.totalUsage)`
- 記憶體: `MetricStatus.capacity(memory.usedFraction)`
- 磁碟: `MetricStatus.capacity(disk.usedFraction)`
- 電池: `MetricStatus.battery(chargeFraction:isCharging:)`
- 網路: 暫定 `.normal`

網路速率沒有全域合理門檻:不同網路環境、使用者工作型態差異很大。先維持 normal,避免正常下載或同步被誤標為異常。日後若加入使用者自訂門檻或基準線,再讓網路圖示進入 elevated/critical。

## 技術設計

`SegmentReading` 從「欄位 + 格式化數值」擴充為「欄位 + 格式化數值 + 狀態」:

```swift
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public let status: MetricStatus
}
```

`MenuBarText.readings(snapshot:segments:)` 在核心層同時計算 `value` 與 `status`。這讓單元測試可以覆蓋狀態邏輯,也讓 SwiftUI view 不需要理解 CPU/記憶體/磁碟/電池各自的判斷規則。

App 層新增或擴充圖示呈現輔助:

- `MenuBarSegmentIcon.name(for:)` 保留現有 `segment -> SF Symbol` 對應。
- 新增 `MenuBarSegmentIcon.color(for:)` 或獨立 `MenuBarStatusColor.color(for:)`,集中處理 `MetricStatus -> SwiftUI.Color`。

`MenuBarLabel.renderLabel()` 在 `mode == .iconOnly` 時對每個 icon 套用對應狀態色。由於目前 `MenuBarExtra` 透過 `ImageRenderer` 轉成 `NSImage`,實作時需確認:

- 若 `image.isTemplate = true`,系統可能覆蓋自訂顏色。
- 狀態圖示模式需要保留彩色輸出時,應只在非彩色模式使用 template,或依模式設定 `isTemplate`。

## 相容性

`MenuBarDisplayMode` 不新增破壞性 raw value:

```swift
public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconValue
    case iconOnly
}
```

UI label 顯示「狀態圖示」,但 storage 繼續使用 `iconOnly`。這避免既有使用者切到 icon-only 後升級時回到預設模式。

## 測試策略

核心測試:

- `MenuBarTextTests` 驗證每個 `SegmentReading` 包含正確 `status`。
- CPU 0.91 -> `.critical`;記憶體/磁碟 0.82 -> `.elevated`;低電量未充電 -> `.critical`;充電中 -> `.charging`。
- 缺資料、無電池、nil snapshot、空欄位行為維持不變。
- `MenuBarDisplayModeTests` 驗證 raw value `iconOnly` 仍可 round-trip,`allCases` 順序穩定。

App 驗證:

- `xcodebuild` build 成功。
- 在實機或本機 App 中切換「狀態圖示」後,選單列仍顯示已選欄位順序。
- 以可控測試資料或臨時預覽確認 elevated/critical/charging 顏色未被 template image 抹掉。

## 受影響檔案

預期修改:

- `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
- `Tests/GlanceCoreTests/MenuBarTextTests.swift`
- `Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift`
- `GlanceApp/MenuBar/MenuBarLabel.swift`
- `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`
- `GlanceApp/Settings/SettingsView.swift`

可能視實作需要新增:

- `GlanceApp/MenuBar/MenuBarStatusColor.swift`

## 自查

- 無 TBD/TODO。
- 設計與既有 `MetricStatus`、`MenuBarText.readings`、`MenuBarDisplayMode.iconOnly` 相容。
- 網路狀態明確暫不告警,避免模糊門檻。
- 範圍聚焦於讓「僅圖示」有狀態意義,不擴張到通知或新設定。
