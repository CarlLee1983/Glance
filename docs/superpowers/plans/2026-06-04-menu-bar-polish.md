# 選單列體驗完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 Glance 選單列補齊開機自啟、磁碟/電池欄位與自訂排序,並提供「圖示+數值 / 僅圖示」顯示樣式以利瀏海機型。

**Architecture:** 核心 `GlanceCore` 維持純資料層 —— `MenuBarText.readings(...)` 回傳有序的 `[SegmentReading]`(欄位+數值字串),可單元測試;圖示對應與呈現模式放在 App 層(SwiftUI),`@AppStorage` 驅動。登入項以 `SMAppService.mainApp`(macOS 13+)實作,封裝於 `LoginItemController`。

**Tech Stack:** Swift 5.9 / SwiftUI / `MenuBarExtra` / XCTest / `ServiceManagement.SMAppService` / SwiftPM(`swift test`)+ XcodeGen/xcodebuild(App 建置)。

---

## 檔案結構

| 檔案 | 職責 | 動作 |
| --- | --- | --- |
| `Sources/GlanceCore/MenuBar/MenuBarSegment.swift` | `MenuBarSegment` 列舉(+disk/battery)、`MenuBarDisplayMode`、`SegmentReading`、`MenuBarText.readings` | 改寫 |
| `Tests/GlanceCoreTests/MenuBarTextTests.swift` | readings 邏輯單元測試 | 改寫 |
| `GlanceApp/MenuBar/MenuBarSegmentIcon.swift` | `segment → SF Symbol` 名稱對應 | 新增 |
| `GlanceApp/MenuBar/MenuBarLabel.swift` | 依模式渲染圖示/數值 | 改寫 |
| `GlanceApp/Login/LoginItemController.swift` | `SMAppService` 開機自啟包裝 | 新增 |
| `GlanceApp/Settings/SettingsView.swift` | 登入 Toggle、樣式 Picker、可排序欄位 List、disk/battery 標籤 | 改寫 |
| `README.md` | 反映新功能 | 改寫 |

核心型別介面(後續任務一致沿用):

```swift
public enum MenuBarSegment: String, CaseIterable, Codable { case cpu, memory, network, disk, battery }
public enum MenuBarDisplayMode: String, CaseIterable, Codable { case iconValue, iconOnly }
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public init(segment: MenuBarSegment, value: String)
}
public enum MenuBarText {
    public static func readings(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> [SegmentReading]
}
```

App 層共用對應:`MenuBarSegmentIcon.name(for:) -> String`;`@AppStorage` 鍵:`menuBarSegments`(逗號字串,保序)、`menuBarDisplayMode`(預設 `iconValue`)、`refreshInterval`。

---

### Task 1: 核心 —— 欄位擴充、顯示模式、readings

**Files:**
- Modify: `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
- Test: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1: 改寫失敗測試**

把 `Tests/GlanceCoreTests/MenuBarTextTests.swift` 整檔替換為:

```swift
import XCTest
@testable import GlanceCore

final class MenuBarTextTests: XCTestCase {
    private func makeSnapshot(disk: DiskSnapshot? = nil, battery: BatteryStats? = nil) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.23, user: 0.23, system: 0, idle: 0.77),
            memory: MemorySnapshot(usedBytes: 61, totalBytes: 100, swapUsedBytes: 0, pressure: .normal),
            network: NetworkSnapshot(downBytesPerSec: 2_202_009, upBytesPerSec: 0, totalDownBytes: 0, totalUpBytes: 0),
            disk: disk, battery: battery, topByCPU: [], topByMemory: [])
    }

    func testReadingsFollowSegmentOrder() {
        let r = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.network, .cpu, .memory])
        XCTAssertEqual(r, [
            SegmentReading(segment: .network, value: "2.1M"),
            SegmentReading(segment: .cpu, value: "23%"),
            SegmentReading(segment: .memory, value: "61%"),
        ])
    }

    func testDiskAndBatteryReadings() {
        let snap = makeSnapshot(
            disk: DiskSnapshot(totalBytes: 100, usedBytes: 71),
            battery: BatteryStats(isPresent: true, chargeFraction: 0.99, isCharging: false))
        let r = MenuBarText.readings(snapshot: snap, segments: [.disk, .battery])
        XCTAssertEqual(r, [
            SegmentReading(segment: .disk, value: "71%"),
            SegmentReading(segment: .battery, value: "99%"),
        ])
    }

    func testAbsentBatteryIsSkipped() {
        let snap = makeSnapshot(battery: BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false))
        XCTAssertEqual(MenuBarText.readings(snapshot: snap, segments: [.battery]), [])
    }

    func testMissingMetricIsSkipped() {
        // disk 未提供 → 該欄位略過,只剩 cpu
        let r = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.cpu, .disk])
        XCTAssertEqual(r, [SegmentReading(segment: .cpu, value: "23%")])
    }

    func testNilSnapshotReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: nil, segments: [.cpu]), [])
    }

    func testEmptySegmentsReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: makeSnapshot(), segments: []), [])
    }

    func testDisplayModeRoundTrips() {
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconOnly"), .iconOnly)
        XCTAssertEqual(MenuBarDisplayMode.allCases, [.iconValue, .iconOnly])
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter MenuBarTextTests`
Expected: 編譯失敗 —— `readings`、`SegmentReading`、`MenuBarDisplayMode`、`.disk`、`.battery` 未定義。

- [ ] **Step 3: 實作核心**

把 `Sources/GlanceCore/MenuBar/MenuBarSegment.swift` 整檔替換為:

```swift
/// 選單列上可顯示的欄位。allCases 的順序即為預設顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, battery
}

/// 選單列呈現模式。
public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconValue  // 圖示 + 數值
    case iconOnly   // 僅圖示(最省寬度)
}

/// 單一欄位的選單列讀數:欄位身分 + 已格式化的數值字串(不含圖示/箭頭)。
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public init(segment: MenuBarSegment, value: String) {
        self.segment = segment
        self.value = value
    }
}

/// 依選定欄位與順序,把 snapshot 轉成有序讀數。圖示與排版交由 App 層。
/// snapshot 為 nil、欄位資料缺漏、或電池不存在時,該筆略過。
public enum MenuBarText {
    public static func readings(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> [SegmentReading] {
        guard let snapshot else { return [] }
        var out: [SegmentReading] = []
        for seg in segments {
            switch seg {
            case .cpu:
                if let c = snapshot.cpu {
                    out.append(SegmentReading(segment: .cpu, value: Formatters.percent(c.totalUsage)))
                }
            case .memory:
                if let m = snapshot.memory {
                    out.append(SegmentReading(segment: .memory, value: Formatters.percent(m.usedFraction)))
                }
            case .network:
                if let n = snapshot.network {
                    out.append(SegmentReading(segment: .network, value: Formatters.rateCompact(n.downBytesPerSec)))
                }
            case .disk:
                if let d = snapshot.disk {
                    out.append(SegmentReading(segment: .disk, value: Formatters.percent(d.usedFraction)))
                }
            case .battery:
                if let b = snapshot.battery, b.isPresent {
                    out.append(SegmentReading(segment: .battery, value: Formatters.percent(b.chargeFraction)))
                }
            }
        }
        return out
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter MenuBarTextTests`
Expected: PASS(7 個測試全綠)。

> 註:此步後 App 端 `MenuBarLabel` 仍呼叫舊 `compose`,App build 會暫時失敗;`swift test` 不編譯 App target 故維持綠燈。App 端於 Task 3 修正,整體建置於 Task 6 驗證。

- [ ] **Step 5: 提交**

```bash
git add Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift
git commit -m "feat: [core] 選單列 readings 改有序結構並新增 disk/battery 與顯示模式"
```

---

### Task 2: App —— 欄位圖示對應

**Files:**
- Create: `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`

- [ ] **Step 1: 新增圖示對應**

建立 `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`:

```swift
import GlanceCore

/// 選單列欄位對應的 SF Symbol 名稱。集中於此,方便日後調整圖示。
enum MenuBarSegmentIcon {
    static func name(for segment: MenuBarSegment) -> String {
        switch segment {
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .network: return "arrow.down"
        case .disk:    return "internaldrive"
        case .battery: return "battery.100"
        }
    }
}
```

- [ ] **Step 2: 提交**

此為純常數對應、無單元測試(整體建置於 Task 6 驗證)。

```bash
git add GlanceApp/MenuBar/MenuBarSegmentIcon.swift
git commit -m "feat: [app] 新增選單列欄位 SF Symbol 對應"
```

---

### Task 3: App —— MenuBarLabel 依模式渲染

**Files:**
- Modify: `GlanceApp/MenuBar/MenuBarLabel.swift`

- [ ] **Step 1: 改寫 MenuBarLabel**

把 `GlanceApp/MenuBar/MenuBarLabel.swift` 整檔替換為:

```swift
import SwiftUI
import GlanceCore

/// 選單列常駐標籤:依顯示模式呈現「圖示+數值」或「僅圖示」。
/// 首次出現時啟動取樣計時器,頻率變更時重啟。
struct MenuBarLabel: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"
    @AppStorage("menuBarDisplayMode") private var displayModeRaw: String = MenuBarDisplayMode.iconValue.rawValue

    private var segments: [MenuBarSegment] {
        segmentsRaw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
    }
    private var mode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRaw) ?? .iconValue
    }

    var body: some View {
        content
            .monospacedDigit()
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }

    /// 以單一 `Text` 內插 SF Symbol —— `MenuBarExtra` label 最可靠的渲染方式。
    private var content: Text {
        let readings = MenuBarText.readings(snapshot: store.snapshot, segments: segments)
        guard !readings.isEmpty else { return Text(verbatim: "—") }
        var result = Text(verbatim: "")
        for (i, r) in readings.enumerated() {
            if i > 0 { result = result + Text(verbatim: " ") }
            let icon = Text("\(Image(systemName: MenuBarSegmentIcon.name(for: r.segment)))")
            switch mode {
            case .iconValue: result = result + icon + Text(verbatim: " " + r.value)
            case .iconOnly:  result = result + icon
            }
        }
        return result
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add GlanceApp/MenuBar/MenuBarLabel.swift
git commit -m "feat: [app] 選單列依模式渲染圖示與數值"
```

---

### Task 4: App —— 開機自啟控制器

**Files:**
- Create: `GlanceApp/Login/LoginItemController.swift`

- [ ] **Step 1: 新增 LoginItemController**

建立 `GlanceApp/Login/LoginItemController.swift`:

```swift
import SwiftUI
import ServiceManagement

/// 包裝 `SMAppService.mainApp` 的開機自啟開關。切換失敗時還原狀態並提供錯誤訊息,不靜默吞錯。
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var errorMessage: String?

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "設定登入啟動失敗:\(error.localizedDescription)"
        }
        // 一律以系統實際狀態為準,失敗時開關自動還原。
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }
}
```

- [ ] **Step 2: 提交**

系統 API,無單元測試,Task 6 後實機驗證(手動開關 + 登出登入確認)。

```bash
git add GlanceApp/Login/LoginItemController.swift
git commit -m "feat: [app] 以 SMAppService 實作開機自啟控制器"
```

---

### Task 5: App —— 設定頁(登入/樣式/排序/新標籤)

**Files:**
- Modify: `GlanceApp/Settings/SettingsView.swift`

- [ ] **Step 1: 改寫 SettingsView**

把 `GlanceApp/Settings/SettingsView.swift` 整檔替換為:

```swift
import SwiftUI
import GlanceCore

/// 設定:開機自啟、更新頻率、選單列樣式、選單列欄位(可勾選 + 可拖曳排序)。
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarDisplayMode") private var displayModeRaw: String = MenuBarDisplayMode.iconValue.rawValue
    @StateObject private var loginItem = LoginItemController()

    // 欄位順序與啟用狀態:由 menuBarSegments 種子,持久化時寫回同一鍵(保序)。
    @State private var order: [MenuBarSegment]
    @State private var enabled: Set<MenuBarSegment>

    init() {
        let raw = UserDefaults.standard.string(forKey: "menuBarSegments") ?? "cpu,memory,network"
        let selected = raw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
        let rest = MenuBarSegment.allCases.filter { !selected.contains($0) }
        _order = State(initialValue: selected + rest)
        _enabled = State(initialValue: Set(selected))
    }

    var body: some View {
        Form {
            Section("一般") {
                Toggle("登入時啟動 Glance", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                if let msg = loginItem.errorMessage {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
            Section("更新頻率") {
                Slider(value: $refreshInterval, in: 1...5, step: 1)
                Text("每 \(Int(refreshInterval)) 秒更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列樣式") {
                Picker("樣式", selection: $displayModeRaw) {
                    Text("圖示 + 數值").tag(MenuBarDisplayMode.iconValue.rawValue)
                    Text("僅圖示").tag(MenuBarDisplayMode.iconOnly.rawValue)
                }
                .pickerStyle(.radioGroup)
                Text("瀏海機型可選「僅圖示」最省選單列寬度")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列欄位(拖曳調整順序)") {
                List {
                    ForEach(order, id: \.self) { seg in
                        Toggle(label(seg), isOn: Binding(
                            get: { enabled.contains(seg) },
                            set: { on in
                                if on { enabled.insert(seg) } else { enabled.remove(seg) }
                                persist()
                            }))
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        persist()
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// 只把「啟用中」的欄位依目前順序寫回 menuBarSegments(逗號字串保序)。
    private func persist() {
        let raw = order.filter { enabled.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: "menuBarSegments")
    }

    private func label(_ s: MenuBarSegment) -> String {
        switch s {
        case .cpu:     return "CPU"
        case .memory:  return "記憶體"
        case .network: return "網路"
        case .disk:    return "磁碟"
        case .battery: return "電池"
        }
    }
}
```

- [ ] **Step 2: 提交**

```bash
git add GlanceApp/Settings/SettingsView.swift
git commit -m "feat: [app] 設定頁加入登入自啟、顯示樣式與可排序欄位"
```

---

### Task 6: 整體建置與文件

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 確認 XcodeGen 可用**

Run: `which xcodegen || brew install xcodegen`
Expected: 印出 xcodegen 路徑(或完成安裝)。

- [ ] **Step 2: 產生專案並建置**

Run:
```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`。若失敗,依錯誤定位到對應任務檔案修正後重跑。

- [ ] **Step 3: 跑完整核心測試**

Run: `swift test`
Expected: 全部測試 PASS。

- [ ] **Step 4: 更新 README**

在 `README.md` 的「選單列 App(GlanceApp)」段落,將描述更新為涵蓋新功能。把該段第一段(目前說明點開有哪些區塊、設定可調項目的文字)替換為:

```markdown
建置後於產物路徑 `open Glance.app` 即在選單列常駐。點開有 CPU/記憶體/網路/磁碟/電池 區塊(CPU/記憶體含歷史曲線與 Top 程式)。下拉內可開「設定…」:

- **登入時啟動 Glance**(`SMAppService`)
- **更新頻率**(1~5 秒)
- **選單列樣式**:圖示+數值 / 僅圖示(瀏海機型建議「僅圖示」最省寬度)
- **選單列欄位**:CPU/記憶體/網路/磁碟/電池,可勾選並拖曳調整顯示順序
```

- [ ] **Step 5: 提交**

```bash
git add README.md
git commit -m "docs: 更新 README 反映選單列新功能"
```

- [ ] **Step 6: 實機驗證(手動)**

`open` 建置產物後確認:
1. 選單列顯示圖示+數值;設定切「僅圖示」後只剩圖示。
2. 設定勾選磁碟/電池並拖曳排序,選單列即時反映順序。
3. 「登入時啟動」開關可開可關;關閉再開不報錯。失敗時顯示紅字且開關還原。
4. 在內建(瀏海)螢幕用「僅圖示」確認寬度縮小、不易被遮蔽。

---

## Self-Review

**Spec coverage:**
- 開機自啟 → Task 4(控制器)+ Task 5(Toggle)✅
- 欄位完整化(disk/battery)→ Task 1(readings)+ Task 5(標籤/勾選)✅
- 自訂排序 → Task 5(List + .onMove + persist 保序)✅
- 顯示樣式(圖示+數值/僅圖示)→ Task 1(模式列舉)+ Task 2(圖示)+ Task 3(渲染)+ Task 5(Picker)✅
- 測試策略(readings 順序/disk/battery/nil/空/不存在電池)→ Task 1 七個測試 ✅
- 受影響檔案全數對應任務 ✅

**Placeholder scan:** 無 TBD/TODO;每個程式步驟均含完整程式碼。

**Type consistency:** `MenuBarSegment`(5 cases)、`MenuBarDisplayMode`(iconValue/iconOnly)、`SegmentReading(segment:value:)`、`MenuBarText.readings(snapshot:segments:)`、`MenuBarSegmentIcon.name(for:)`、`@AppStorage` 鍵(`menuBarSegments`/`menuBarDisplayMode`/`refreshInterval`)在 Task 1/2/3/5 間一致。
```
