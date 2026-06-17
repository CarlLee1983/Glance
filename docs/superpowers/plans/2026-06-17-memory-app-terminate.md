# 記憶體區「結束高佔用 App」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在儀錶板記憶體卡片的「高記憶體應用排行」中,對 `.app` 類 App 提供 hover「結束」鈕 → 輕量確認 → graceful terminate。

**Architecture:** 純比對邏輯 `AppTerminationMatcher`(以 `bundleURL` 比對找回 running app)放進可測的 GlanceCore;AppKit 副作用 `AppTerminator`(注入式 `terminate`)為薄層;`AppMemoryList` 加 hover 鈕 + `NSAlert` 確認。沿用 `Uninstaller` 的「動作可注入」hermetic 測試模式。

**Tech Stack:** Swift / SwiftPM、AppKit(`NSRunningApplication`、`NSWorkspace`、`NSAlert`)、SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-06-17-memory-app-terminate-design.md`

**分支:** `feat/memory-app-terminate`(已建立)

---

## File Structure

| 動作 | 檔案 | 責任 |
|------|------|------|
| Create | `Sources/GlanceCore/Process/AppTerminationMatcher.swift` | `RunningAppRef` 型別 + 純比對函式 |
| Create | `Tests/GlanceCoreTests/AppTerminationMatcherTests.swift` | matcher 單元測試 |
| Create | `GlanceApp/Components/AppTerminator.swift` | AppKit 薄層:映射 running apps、呼叫注入式 terminate |
| Modify | `GlanceApp/Components/AppMemoryList.swift` | hover「結束」鈕、eligibility 判斷、`NSAlert` 確認、串接 `AppTerminator` |

GlanceApp 無 test target(同 `CleanupViewModel`/`UninstallViewModel` 既有取捨),故 TDD 僅施於 GlanceCore 的 matcher;`AppTerminator` 與 UI 以 `swift build` 編譯驗證 + 使用者實機驗收。

---

## Task 1: AppTerminationMatcher(GlanceCore 純比對)

**Files:**
- Create: `Sources/GlanceCore/Process/AppTerminationMatcher.swift`
- Test: `Tests/GlanceCoreTests/AppTerminationMatcherTests.swift`

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/AppTerminationMatcherTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class AppTerminationMatcherTests: XCTestCase {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testReturnsMatchingRunningApp() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertEqual(result, running)
    }

    func testExcludesCurrentApp() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: true)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsEmptyWhenNoMatch() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Bar.app"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsAllInstancesWithSameBundle() {
        let a = RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)
        let b = RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: [a, b])
        XCTAssertEqual(result.count, 2)
    }

    func testMatchesDespitePathRepresentationDifferences() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app/"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/./Foo.app"), running: running)
        XCTAssertEqual(result.count, 1)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter AppTerminationMatcherTests`
Expected: 編譯失敗 —— `cannot find 'RunningAppRef' / 'AppTerminationMatcher' in scope`。

- [ ] **Step 3: 寫最小實作**

建立 `Sources/GlanceCore/Process/AppTerminationMatcher.swift`:

```swift
import Foundation

/// running app 的輕量描述,讓比對邏輯與 AppKit 解耦、可單元測試。
public struct RunningAppRef: Equatable {
    public let bundleURL: URL
    public let isCurrentApp: Bool
    public init(bundleURL: URL, isCurrentApp: Bool) {
        self.bundleURL = bundleURL
        self.isCurrentApp = isCurrentApp
    }
}

/// 純比對:給定目標 .app 的 bundleURL 與一組 running app,
/// 回傳「bundleURL 標準化後相符且非自身」的項目(可能多個實例)。
public enum AppTerminationMatcher {
    public static func matches(target: URL, running: [RunningAppRef]) -> [RunningAppRef] {
        let key = target.standardizedFileURL.path
        return running.filter { ref in
            !ref.isCurrentApp && ref.bundleURL.standardizedFileURL.path == key
        }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter AppTerminationMatcherTests`
Expected: PASS(5 tests)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Process/AppTerminationMatcher.swift Tests/GlanceCoreTests/AppTerminationMatcherTests.swift
git commit -m "feat: [core] AppTerminationMatcher 以 bundleURL 比對找回可結束 app"
```

---

## Task 2: AppTerminator(GlanceApp AppKit 薄層)

**Files:**
- Create: `GlanceApp/Components/AppTerminator.swift`

GlanceApp 無 test target,本任務以 `swift build` 編譯驗證。注入式 `terminate` / `runningApps` 讓核心可在不真正殺 App 下被將來測試。

- [ ] **Step 1: 寫實作**

建立 `GlanceApp/Components/AppTerminator.swift`:

```swift
import AppKit
import GlanceCore

/// 把 NSRunningApplication 映射成 RunningAppRef 餵給 AppTerminationMatcher,
/// 再對相符者執行 graceful terminate。動作以 closure 注入以利測試/替身。
struct AppTerminator {
    /// 對單一 running app 執行的結束動作(預設 graceful terminate)。
    var terminate: (NSRunningApplication) -> Void = { _ = $0.terminate() }

    /// 列舉目前 running apps(預設取系統清單)。
    var runningApps: () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }

    /// 結束所有 bundleURL 與 target 相符且非自身的 running app(同 app 多實例全數結束)。
    /// 找不到相符(例如 App 已自行退出)時為安全 no-op。回傳實際嘗試結束的數量。
    @discardableResult
    func terminateApp(matching target: URL) -> Int {
        let apps = runningApps()
        let refs = apps.compactMap { app -> RunningAppRef? in
            guard let url = app.bundleURL else { return nil }
            return RunningAppRef(bundleURL: url, isCurrentApp: app == .current)
        }
        let wantedPaths = Set(
            AppTerminationMatcher.matches(target: target, running: refs)
                .map { $0.bundleURL.standardizedFileURL.path }
        )
        let toTerminate = apps.filter { app in
            guard let url = app.bundleURL, app != .current else { return false }
            return wantedPaths.contains(url.standardizedFileURL.path)
        }
        toTerminate.forEach { terminate($0) }
        return toTerminate.count
    }
}
```

- [ ] **Step 2: 編譯驗證**

Run: `swift build`
Expected: build 成功,無 warning/error。

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/Components/AppTerminator.swift
git commit -m "feat: [app] AppTerminator graceful 結束相符 running app"
```

---

## Task 3: AppMemoryList hover「結束」鈕 + 確認

**Files:**
- Modify: `GlanceApp/Components/AppMemoryList.swift`

在每列(可結束者)hover 時淡入小「結束」鈕,點擊跳 `NSAlert` 確認後呼叫 `AppTerminator`。可結束 = 有 `bundleURL` 且非 Glance 自身(該 App 已在記憶體排行中即代表正在執行;競態由 `AppTerminator` 的 no-op 兜底)。

- [ ] **Step 1: 加入 terminator、hover 狀態與 eligibility 判斷**

在 `AppMemoryList` struct 內(`@State private var expanded = false` 之後)新增:

```swift
    @State private var hoveredID: String?

    private let terminator = AppTerminator()
```

並在 `private let collapsedCount = 5` 之後新增兩個私有方法:

```swift
    /// 可結束:有 .app bundle 且不是 Glance 自身。
    private func eligible(_ app: AppMemoryUsage) -> Bool {
        guard let url = app.bundleURL else { return false }
        return url.standardizedFileURL.path != Bundle.main.bundleURL?.standardizedFileURL.path
    }

    /// 輕量確認 → graceful terminate。
    private func confirmAndTerminate(_ app: AppMemoryUsage) {
        guard let url = app.bundleURL else { return }
        let alert = NSAlert()
        alert.messageText = "確定要結束「\(app.appName)」嗎?"
        alert.informativeText = "未儲存的資料可能遺失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "結束")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            terminator.terminateApp(matching: url)
        }
    }
```

- [ ] **Step 2: 在 row 加入 hover 鈕並接 onHover**

把 `row(_:isTop:maxVal:)` 內 `Spacer()` 與位元組 `Text(...)` 之間插入結束鈕,並在整個 row 的 `HStack { ... }` 鏈尾(`.background(...)` 之後)加 `.onHover`。

修改後的 `row` 方法完整內容:

```swift
    private func row(_ app: AppMemoryUsage, isTop: Bool, maxVal: Double) -> some View {
        let ratio = min(max(Double(app.memoryBytes) / maxVal, 0.0), 1.0)
        let showKill = hoveredID == app.id && eligible(app)

        return HStack(spacing: 8) {
            icon(for: app)
                .resizable()
                .frame(width: isTop ? 22 : 16, height: isTop ? 22 : 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.appName)
                        .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isTop {
                        Text("最佔用")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accent.opacity(0.18), in: Capsule())
                    }
                }
                if app.processCount > 1 {
                    Text("\(app.processCount) 個行程")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if showKill {
                Button {
                    confirmAndTerminate(app)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("結束「\(app.appName)」")
                .transition(.opacity)
            }

            Text(Formatters.bytes(app.memoryBytes))
                .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isTop ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isTop ? 5 : 3)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(isTop ? 0.14 : 0.07))
                    .frame(width: geo.size.width * CGFloat(ratio))
            }
        }
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                if inside { hoveredID = app.id }
                else if hoveredID == app.id { hoveredID = nil }
            }
        }
    }
```

- [ ] **Step 3: 編譯驗證**

Run: `swift build`
Expected: build 成功。

- [ ] **Step 4: 全套件測試(確保未破壞既有)**

Run: `swift test`
Expected: 全綠(既有 131 + 新增 5 = 136)。

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/Components/AppMemoryList.swift
git commit -m "feat: [app] 記憶體排行 hover 結束鈕 + 確認"
```

---

## Task 4: 實機驗收(使用者觸發)

**非自動化** —— 比照 cleanup/uninstall,破壞性動作的實機驗收留給使用者。

- [ ] **Step 1: 啟動 App**

依 [[verify-by-launching-app]] 慣例組裝並啟動 `.app`(`swift build` 後手動組 bundle,見 brew 打包筆記),非僅靠 `swift test`/`swift build` 綠燈。

- [ ] **Step 2: 手動驗收清單**

- [ ] 開選單列下拉 → 記憶體卡片 → 高記憶體應用排行。
- [ ] hover 一個 `.app`(如 Chrome)→ 右側出現 `xmark.circle.fill`。
- [ ] hover Glance 自身那列(若出現在排行)→ **不應**出現結束鈕。
- [ ] 點結束鈕 → 跳「確定要結束「X」嗎?」alert。
- [ ] 取消 → 無事發生。
- [ ] 確認 → 目標 App graceful 結束(有未存內容者自行跳儲存對話框)→ 下一取樣週期該列消失/更新。
- [ ] CLI 工具類 entry(顯示「N 個行程」、無 app 圖示)→ hover **不應**出現結束鈕。

---

## Self-Review 紀錄

- **Spec coverage:** 核心機制(bundleURL 比對)→ Task 1;分層(GlanceCore matcher / GlanceApp terminator)→ Task 1+2;UX(hover 鈕、NSAlert 確認、排除自身、非 .app 不顯示)→ Task 3;競態 no-op → Task 2 `terminateApp` 註解 + 實作;測試策略 → Task 1 五案;實機破壞性驗收 → Task 4。皆有對應任務。
- **Placeholder scan:** 無 TBD/TODO;每個 code step 均含完整程式碼。
- **Type consistency:** `RunningAppRef`(bundleURL/isCurrentApp)、`AppTerminationMatcher.matches(target:running:)`、`AppTerminator.terminateApp(matching:)`、`eligible(_:)`、`confirmAndTerminate(_:)`、`hoveredID` 在各任務間命名一致。
