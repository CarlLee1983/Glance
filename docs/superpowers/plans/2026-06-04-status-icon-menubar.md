# Status Icon Menubar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing icon-only menubar mode into a meaningful status-icon mode where each selected metric icon communicates normal/elevated/critical/charging state without adding width.

**Architecture:** Keep metric state decisions in `GlanceCore` by extending `SegmentReading` with `MetricStatus`. Keep SwiftUI/AppKit presentation in `GlanceApp`: segment-to-symbol stays in `MenuBarSegmentIcon`, status-to-color lives in a focused app helper, and `MenuBarLabel` decides whether rendered output should be template or full color.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit `NSImage`, `ImageRenderer`, XCTest, SwiftPM, XcodeGen/xcodebuild.

---

## Preconditions

The current worktree already contains unrelated or earlier UI/status changes:

- `GlanceApp/Components/TopProcessList.swift`
- `GlanceApp/Dropdown/*.swift`
- `GlanceApp/Dropdown/DropdownChrome.swift`
- `Sources/GlanceCore/Format/MetricStatus.swift`
- `Tests/GlanceCoreTests/MetricStatusTests.swift`

Do not revert or restage those files unless a task below explicitly touches them. `MetricStatus` is treated as an existing core type for this plan.

## File Structure

| File | Responsibility | Action |
| --- | --- | --- |
| `Sources/GlanceCore/MenuBar/MenuBarSegment.swift` | Menu bar segment enum, display mode enum, formatted readings and core status calculation | Modify |
| `Tests/GlanceCoreTests/MenuBarTextTests.swift` | Unit coverage for ordered readings, formatted values, status values, missing data behavior | Modify |
| `Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift` | Storage compatibility for `iconOnly` raw value | Modify |
| `GlanceApp/MenuBar/MenuBarSegmentIcon.swift` | Segment-to-SF-Symbol mapping only | Leave focused; no status color here |
| `GlanceApp/MenuBar/MenuBarStatusColor.swift` | App-layer mapping from `MetricStatus` to SwiftUI color | Create |
| `GlanceApp/MenuBar/MenuBarLabel.swift` | Render icon/value or status-icon label and preserve status colors in icon-only mode | Modify |
| `GlanceApp/Settings/SettingsView.swift` | Rename UI copy from "僅圖示" to "狀態圖示" while preserving `iconOnly` storage | Modify |

---

### Task 1: Core Readings Carry Metric Status

**Files:**
- Modify: `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
- Test: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1: Replace `MenuBarTextTests` with failing status-aware tests**

Replace `Tests/GlanceCoreTests/MenuBarTextTests.swift` with:

```swift
import XCTest
@testable import GlanceCore

final class MenuBarTextTests: XCTestCase {
    private func makeSnapshot(
        cpuUsage: Double = 0.23,
        memoryUsedFraction: Double = 0.61,
        networkDownBytesPerSec: Double = 2_202_009,
        disk: DiskSnapshot? = nil,
        battery: BatteryStats? = nil
    ) -> SystemSnapshot {
        SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: cpuUsage, user: cpuUsage, system: 0, idle: 1 - cpuUsage),
            memory: MemorySnapshot(
                usedBytes: UInt64(memoryUsedFraction * 100),
                totalBytes: 100,
                swapUsedBytes: 0,
                pressure: .normal
            ),
            network: NetworkSnapshot(
                downBytesPerSec: networkDownBytesPerSec,
                upBytesPerSec: 0,
                totalDownBytes: 0,
                totalUpBytes: 0
            ),
            disk: disk,
            battery: battery,
            topByCPU: [],
            topByMemory: []
        )
    }

    func testReadingsFollowSegmentOrderAndIncludeStatus() {
        let readings = MenuBarText.readings(
            snapshot: makeSnapshot(cpuUsage: 0.91, memoryUsedFraction: 0.82),
            segments: [.network, .cpu, .memory]
        )

        XCTAssertEqual(readings, [
            SegmentReading(segment: .network, value: "2.1M", status: .normal),
            SegmentReading(segment: .cpu, value: "91%", status: .critical),
            SegmentReading(segment: .memory, value: "82%", status: .elevated),
        ])
    }

    func testDiskAndBatteryReadingsIncludeStatus() {
        let snapshot = makeSnapshot(
            disk: DiskSnapshot(totalBytes: 100, usedBytes: 93),
            battery: BatteryStats(isPresent: true, chargeFraction: 0.18, isCharging: false)
        )

        let readings = MenuBarText.readings(snapshot: snapshot, segments: [.disk, .battery])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .disk, value: "93%", status: .critical),
            SegmentReading(segment: .battery, value: "18%", status: .critical),
        ])
    }

    func testChargingBatteryUsesChargingStatus() {
        let snapshot = makeSnapshot(
            battery: BatteryStats(isPresent: true, chargeFraction: 0.81, isCharging: true)
        )

        let readings = MenuBarText.readings(snapshot: snapshot, segments: [.battery])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .battery, value: "81%", status: .charging),
        ])
    }

    func testAbsentBatteryIsSkipped() {
        let snapshot = makeSnapshot(
            battery: BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        )

        XCTAssertEqual(MenuBarText.readings(snapshot: snapshot, segments: [.battery]), [])
    }

    func testMissingMetricIsSkipped() {
        let readings = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.cpu, .disk])

        XCTAssertEqual(readings, [
            SegmentReading(segment: .cpu, value: "23%", status: .normal),
        ])
    }

    func testNilSnapshotReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: nil, segments: [.cpu]), [])
    }

    func testEmptySegmentsReturnsEmpty() {
        XCTAssertEqual(MenuBarText.readings(snapshot: makeSnapshot(), segments: []), [])
    }
}
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run:

```bash
swift test --filter MenuBarTextTests
```

Expected: FAIL at compile time because `SegmentReading` does not yet accept `status:`.

- [ ] **Step 3: Extend `SegmentReading` and core status calculation**

Replace `Sources/GlanceCore/MenuBar/MenuBarSegment.swift` with:

```swift
/// 選單列上可顯示的欄位。allCases 的順序即為預設顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, battery
}

/// 選單列呈現模式。
public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconValue  // 圖示 + 數值
    case iconOnly   // 狀態圖示;raw value 保留以維持 UserDefaults 相容
}

/// 單一欄位的選單列讀數:欄位身分 + 已格式化數值 + 粗略狀態。
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public let status: MetricStatus

    public init(segment: MenuBarSegment, value: String, status: MetricStatus) {
        self.segment = segment
        self.value = value
        self.status = status
    }
}

/// 依選定欄位與順序,把 snapshot 轉成有序讀數。圖示與排版交由 App 層。
/// snapshot 為 nil、欄位資料缺漏、或電池不存在時,該筆略過。
public enum MenuBarText {
    public static func readings(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> [SegmentReading] {
        guard let snapshot else { return [] }
        var result: [SegmentReading] = []

        for segment in segments {
            switch segment {
            case .cpu:
                if let cpu = snapshot.cpu {
                    result.append(SegmentReading(
                        segment: .cpu,
                        value: Formatters.percent(cpu.totalUsage),
                        status: MetricStatus.load(fraction: cpu.totalUsage)
                    ))
                }
            case .memory:
                if let memory = snapshot.memory {
                    result.append(SegmentReading(
                        segment: .memory,
                        value: Formatters.percent(memory.usedFraction),
                        status: MetricStatus.capacity(fraction: memory.usedFraction)
                    ))
                }
            case .network:
                if let network = snapshot.network {
                    result.append(SegmentReading(
                        segment: .network,
                        value: Formatters.rateCompact(network.downBytesPerSec),
                        status: .normal
                    ))
                }
            case .disk:
                if let disk = snapshot.disk {
                    result.append(SegmentReading(
                        segment: .disk,
                        value: Formatters.percent(disk.usedFraction),
                        status: MetricStatus.capacity(fraction: disk.usedFraction)
                    ))
                }
            case .battery:
                if let battery = snapshot.battery, battery.isPresent {
                    result.append(SegmentReading(
                        segment: .battery,
                        value: Formatters.percent(battery.chargeFraction),
                        status: MetricStatus.battery(
                            chargeFraction: battery.chargeFraction,
                            isCharging: battery.isCharging
                        )
                    ))
                }
            }
        }

        return result
    }
}
```

- [ ] **Step 4: Run the targeted test and verify it passes**

Run:

```bash
swift test --filter MenuBarTextTests
```

Expected: PASS for all `MenuBarTextTests`.

- [ ] **Step 5: Commit the core change**

Run:

```bash
git add Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift
git commit -m "let menubar readings explain status" -m "Constraint: Preserve GlanceCore as the owner of metric threshold decisions.
Rejected: Compute status colors directly in MenuBarLabel | It would duplicate metric thresholds in the UI layer.
Confidence: high
Scope-risk: narrow
Directive: Keep SegmentReading status semantic; avoid adding SwiftUI/AppKit dependencies to GlanceCore.
Tested: swift test --filter MenuBarTextTests
Not-tested: App rendering; handled in later tasks."
```

---

### Task 2: Preserve Display Mode Storage Compatibility

**Files:**
- Modify: `Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift`

- [ ] **Step 1: Replace display mode tests with explicit compatibility coverage**

Replace `Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift` with:

```swift
import XCTest
@testable import GlanceCore

final class MenuBarDisplayModeTests: XCTestCase {
    func testRawValueRoundTripsForStoredValues() {
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconValue"), .iconValue)
        XCTAssertEqual(MenuBarDisplayMode(rawValue: "iconOnly"), .iconOnly)
    }

    func testIconOnlyRawValueRemainsStableForStatusIconMode() {
        XCTAssertEqual(MenuBarDisplayMode.iconOnly.rawValue, "iconOnly")
    }

    func testAllCasesOrder() {
        XCTAssertEqual(MenuBarDisplayMode.allCases, [.iconValue, .iconOnly])
    }
}
```

- [ ] **Step 2: Run the targeted test**

Run:

```bash
swift test --filter MenuBarDisplayModeTests
```

Expected: PASS. If this fails, do not rename the enum case or raw value; fix `MenuBarDisplayMode` to keep `iconOnly`.

- [ ] **Step 3: Commit the compatibility test**

Run:

```bash
git add Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift
git commit -m "lock status icon mode storage compatibility" -m "Constraint: Existing UserDefaults values store iconOnly.
Rejected: Rename the enum case to statusIcon | It would need a migration for no functional gain.
Confidence: high
Scope-risk: narrow
Directive: Rename user-facing copy only; keep raw storage stable.
Tested: swift test --filter MenuBarDisplayModeTests
Not-tested: Settings UI copy; handled in later tasks."
```

---

### Task 3: Add App Status Color Mapping

**Files:**
- Create: `GlanceApp/MenuBar/MenuBarStatusColor.swift`
- Test by build in later task

- [ ] **Step 1: Create the focused color helper**

Create `GlanceApp/MenuBar/MenuBarStatusColor.swift`:

```swift
import SwiftUI
import GlanceCore

/// App 層的狀態色對應。核心只產生語意狀態,不依賴 SwiftUI 顏色。
enum MenuBarStatusColor {
    static func color(for status: MetricStatus) -> Color {
        switch status {
        case .normal:
            return .secondary
        case .elevated:
            return .orange
        case .critical:
            return .red
        case .charging:
            return .green
        }
    }
}
```

- [ ] **Step 2: Verify the helper compiles with the app target**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: build may fail later in `MenuBarLabel` if Task 1 changed `SegmentReading` call sites and they have not been updated yet. It must not fail because `MenuBarStatusColor.swift` is missing imports or target membership.

- [ ] **Step 3: Commit the helper**

Run:

```bash
git add GlanceApp/MenuBar/MenuBarStatusColor.swift
git commit -m "map metric status to menubar colors" -m "Constraint: Keep presentation color decisions in the app target.
Rejected: Add SwiftUI Color to MetricStatus | It would contaminate GlanceCore with UI dependencies.
Confidence: high
Scope-risk: narrow
Directive: Treat these colors as presentation defaults, not metric thresholds.
Tested: xcodegen generate; xcodebuild attempted for compile integration
Not-tested: Final menubar rendering; MenuBarLabel changes follow."
```

---

### Task 4: Render Status Colors in Icon-Only Mode

**Files:**
- Modify: `GlanceApp/MenuBar/MenuBarLabel.swift`

- [ ] **Step 1: Replace `MenuBarLabel` rendering logic**

Replace `GlanceApp/MenuBar/MenuBarLabel.swift` with:

```swift
import SwiftUI
import GlanceCore

/// 選單列常駐標籤:依顯示模式呈現「圖示+數值」或「狀態圖示」。
/// 首次出現時啟動取樣計時器,頻率變更時重啟。
///
/// `MenuBarExtra` label 會丟棄複雜 SwiftUI label 的部分 SF Symbol 呈現,
/// 因此先用 `ImageRenderer` 轉成 `NSImage`。狀態圖示模式必須保留彩色輸出,
/// 不能標成 template image;圖示+數值模式則維持 template,適應系統選單列前景色。
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
        Image(nsImage: renderLabel())
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }

    @MainActor
    private func renderLabel() -> NSImage {
        let readings = MenuBarText.readings(snapshot: store.snapshot, segments: segments)
        let content = HStack(spacing: 6) {
            if readings.isEmpty {
                Text(verbatim: "—")
                    .foregroundStyle(.primary)
            } else {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                    HStack(spacing: 2) {
                        Image(systemName: MenuBarSegmentIcon.name(for: reading.segment))
                            .foregroundStyle(iconColor(for: reading))
                        if mode == .iconValue {
                            Text(reading.value)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        image.isTemplate = mode == .iconValue
        return image
    }

    private func iconColor(for reading: SegmentReading) -> Color {
        switch mode {
        case .iconValue:
            return .primary
        case .iconOnly:
            return MenuBarStatusColor.color(for: reading.status)
        }
    }
}
```

- [ ] **Step 2: Build the app**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: PASS. If `ImageRenderer` output still strips color because of template handling, confirm `image.isTemplate = mode == .iconValue` is present.

- [ ] **Step 3: Commit the rendering change**

Run:

```bash
git add GlanceApp/MenuBar/MenuBarLabel.swift
git commit -m "render icon-only mode as colored status icons" -m "Constraint: MenuBarExtra requires ImageRenderer-based label output for reliable SF Symbol rendering.
Rejected: Always use template NSImage | Template rendering erases per-metric status colors.
Confidence: medium
Scope-risk: moderate
Directive: Keep iconValue template-based; keep iconOnly color-preserving.
Tested: xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
Not-tested: Manual visual confirmation in the live macOS menubar."
```

---

### Task 5: Rename Settings Copy to Status Icon

**Files:**
- Modify: `GlanceApp/Settings/SettingsView.swift`

- [ ] **Step 1: Update only user-facing copy for icon-only mode**

In `GlanceApp/Settings/SettingsView.swift`, find the `Section("選單列樣式")` picker and replace only that section with:

```swift
Section("選單列樣式") {
    Picker("樣式", selection: $displayModeRaw) {
        Text("圖示 + 數值").tag(MenuBarDisplayMode.iconValue.rawValue)
        Text("狀態圖示").tag(MenuBarDisplayMode.iconOnly.rawValue)
    }
    .pickerStyle(.radioGroup)
    Text("狀態圖示會以顏色呈現各欄位狀態,同時維持最省選單列寬度")
        .font(.caption).foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Build the app**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: PASS.

- [ ] **Step 3: Commit the settings copy**

Run:

```bash
git add GlanceApp/Settings/SettingsView.swift
git commit -m "rename icon-only setting to status icons" -m "Constraint: The stored mode remains iconOnly for compatibility.
Rejected: Add a third display mode | The requested behavior replaces meaningless icon-only output rather than adding a new mode.
Confidence: high
Scope-risk: narrow
Directive: User-facing copy may say status icons; storage and enum raw values must stay stable.
Tested: xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
Not-tested: Manual settings interaction in a running app."
```

---

### Task 6: Final Verification

**Files:**
- Verify all changed files

- [ ] **Step 1: Run full SwiftPM tests**

Run:

```bash
swift test
```

Expected: PASS for all core tests.

- [ ] **Step 2: Regenerate and build the app**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: PASS.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
git status --short
git diff -- Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift GlanceApp/MenuBar/MenuBarStatusColor.swift GlanceApp/MenuBar/MenuBarLabel.swift GlanceApp/Settings/SettingsView.swift
```

Expected:

- Only intended status-icon files remain modified or staged.
- `SegmentReading` includes `status`.
- `MenuBarDisplayMode.iconOnly.rawValue` remains `"iconOnly"`.
- `MenuBarLabel` sets `image.isTemplate = mode == .iconValue`.
- Settings copy says `狀態圖示`.

- [ ] **Step 4: Commit any final verification-only adjustments if needed**

If no changes were needed after verification, do not create an empty commit. If a small fix was required, commit it with:

```bash
git add Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift Tests/GlanceCoreTests/MenuBarDisplayModeTests.swift GlanceApp/MenuBar/MenuBarStatusColor.swift GlanceApp/MenuBar/MenuBarLabel.swift GlanceApp/Settings/SettingsView.swift
git commit -m "stabilize status icon verification" -m "Constraint: Final fixes only; no behavior expansion beyond the approved status-icon design.
Rejected: Broaden to network thresholds | No reliable global threshold exists yet.
Confidence: medium
Scope-risk: narrow
Directive: Keep final verification fixes tightly scoped to status-icon behavior.
Tested: swift test; xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
Not-tested: Live menubar color perception on every macOS appearance mode."
```

## Self-Review

- Spec coverage: core status readings, storage compatibility, status colors, ImageRenderer template handling, settings rename, and verification are each covered by tasks.
- Placeholder scan: no TBD/TODO/fill-in instructions remain; commands and expected outcomes are explicit.
- Type consistency: `SegmentReading(segment:value:status:)`, `MetricStatus`, `MenuBarDisplayMode.iconOnly`, and `MenuBarStatusColor.color(for:)` are used consistently across tasks.
- Scope check: network remains `.normal`; no notifications, thresholds, or dropdown redesign are included.
