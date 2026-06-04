# Glance 選單列體驗完善 — 設計文件

- 日期:2026-06-04
- 範圍:三項選單列相關功能(開機自啟、欄位完整化+排序、顯示樣式)
- 不在範圍:新指標(溫度/風扇 SMC、磁碟即時 I/O)、公證、Ice 整合

## 背景與動機

Glance 為 macOS 選單列主機狀態工具。核心資料層 `GlanceCore` 與 `GlanceApp` UI 已具雛形:
選單列可選欄位、下拉有 CPU/記憶體/網路/磁碟/電池(含曲線與 Top 程式)、設定可調頻率與顯示欄位。

本次「完善整體功能」聚焦選單列體驗,補齊以下缺口:

1. 選單列欄位只支援 CPU/記憶體/網路三項,磁碟/電池無法上選單列,且無法自訂順序。
2. 缺少「開機自動啟動」(menu bar app 常駐必備)。
3. 選單列僅純文字,寬度偏大;瀏海機型容易被遮蔽,缺少更精簡的呈現。

`Info.plist` 已設 `LSUIElement`(純選單列、無 Dock 圖示),target macOS 14
→ `SMAppService`(macOS 13+)可直接使用,免舊式 helper bundle。

## 架構取向

選單列要顯示 SF Symbol 圖示,但 `GlanceCore` 必須維持純資料層(不依賴 SwiftUI/AppKit)以保可測。

採取的做法:`MenuBarText.compose` 改回傳**有序的 `[SegmentReading]`**(每筆 = 欄位 + 數值字串);
圖示對應(`segment → SF Symbol`)與呈現模式(圖示+數值 / 僅圖示)放在 App 層。
→ 核心維持純函式可測,測試改驗 readings 陣列;App 層負責視覺。

被否決的替代方案:

- 核心回傳含字形的 `AttributedString` → 核心被迫依賴 SwiftUI,難測。
- 維持回傳 `String`,View 端再解析字串塞圖示 → 脆弱、易壞。

## 功能設計

### 1. 開機自動啟動

- 新檔 `GlanceApp/Login/LoginItemController.swift`:薄包裝 `SMAppService.mainApp`。
  - `var isEnabled: Bool`:讀取 `SMAppService.mainApp.status == .enabled`。
  - `func setEnabled(_ enabled: Bool) throws`:`enabled` 時呼叫 `register()`,否則 `unregister()`。
- 設定頁新增 `Toggle「登入時啟動 Glance」`。
  - 切換失敗(throw)時**還原開關狀態**並顯示一行 caption 說明,不靜默吞錯。
- 系統 API 無法單元測試,以實機驗證(build 後手動開關、重開機或登出登入確認)。

### 2. 選單列欄位完整化 + 排序

- `MenuBarSegment` 列舉新增 `disk`、`battery`(共五項:cpu, memory, network, disk, battery)。
- `MenuBarText.compose` 新增兩 case:
  - `disk` → `Formatters.percent(disk.usedFraction)`
  - `battery` → `Formatters.percent(battery.chargeFraction)`
  - 對應 snapshot 為 nil 時略過該筆(沿用現有行為)。
- 設定頁欄位區改為**可勾選 + 可拖曳排序的 `List`**(`.onMove`)。
  - 順序直接存進現有 `@AppStorage("menuBarSegments")`(逗號字串本就保序)。
  - `MenuBarLabel` 已照存放順序解析,排序天然生效;僅需設定頁 UI 支援。
- `SettingsView.label(_:)` 補上 `disk`(磁碟)、`battery`(電池)中文名。

### 3. 顯示樣式:圖示+數值 / 僅圖示

- 核心新增 `enum MenuBarDisplayMode: String, CaseIterable, Codable { case iconValue, iconOnly }`(純資料,可測)。
- App 層新增 `MenuBarSegmentIcon`(`segment → systemImageName`):
  - cpu=`cpu`、memory=`memorychip`、network=`arrow.down`、disk=`internaldrive`、battery=`battery.100`
- `MenuBarLabel` 依 `@AppStorage("menuBarDisplayMode")`(預設 `iconValue`)與有序 readings 組成
  **單一 `Text`**,以 `Text("\(Image(systemName:)) 23%")` 內插圖示——`MenuBarExtra` label 最可靠的渲染方式。
  - `iconOnly`:只串圖示,不含數值。
- 設定頁新增 `Picker「選單列樣式」`(圖示+數值 / 僅圖示),附提示:瀏海機型選「僅圖示」最省寬度。

## 資料流 / 邊界

- 沿用既有 `@AppStorage` 驅動 `MenuBarLabel` 與 `SettingsView` 的模式,不新增狀態中樞。
- `MenuBarLabel` 已能取 `store.snapshot.disk/battery`,新欄位即時可用。

## 錯誤處理

- 登入項切換失敗:捕捉 `SMAppService` 拋出的錯誤,還原 Toggle、顯示 caption,不中斷 App。
- snapshot 或個別欄位為 nil:該欄位略過;全空或 snapshot 為 nil 時選單列顯示 `—`(現有行為保留)。

## 測試策略

- 改寫 `Tests/GlanceCoreTests/MenuBarTextTests.swift`,驗證:
  - readings 依傳入欄位順序輸出
  - 各欄位數值字串正確(含新增 disk/battery)
  - 個別欄位 snapshot 為 nil 時略過
  - 空欄位 / nil snapshot 的處理
- `MenuBarDisplayMode`、`MenuBarSegmentIcon` 為常數對應,View 層輕測或不測。
- `LoginItemController` 以實機驗證(系統 API)。

## 受影響檔案

改:
- `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`(enum 擴充、`SegmentReading`、`MenuBarDisplayMode`、`compose` 改回傳)
- `GlanceApp/MenuBar/MenuBarLabel.swift`(讀顯示模式 + 有序欄位,渲染圖示/數值)
- `GlanceApp/Settings/SettingsView.swift`(登入 Toggle、樣式 Picker、可排序欄位 List、disk/battery 標籤)
- `Tests/GlanceCoreTests/MenuBarTextTests.swift`(對應新回傳型別)

新:
- `GlanceApp/Login/LoginItemController.swift`(`SMAppService` 包裝)
- `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`(segment → SF Symbol 對應)

## 驗證方式

- `swift test`:核心測試全綠。
- `xcodegen generate` + `xcodebuild ... build`:App 建置成功。
- 實機:選單列圖示/數值正確、設定可勾選與拖曳排序、樣式切換生效、登入項開關有效。
