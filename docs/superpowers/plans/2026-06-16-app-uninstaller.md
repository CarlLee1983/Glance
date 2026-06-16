# App 解除安裝器(階段三) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 App 解除安裝器:列出使用者安裝的 `.app`,以 Bundle ID 嚴格比對找出散落的關聯檔,經確認後把本體與關聯檔移到垃圾桶。

**Architecture:** 純邏輯放 `Sources/GlanceCore/Uninstall/`(模型、寫死位置、安全護欄、App 列舉、關聯檔搜尋、移到垃圾桶執行器,可注入移除動作以利 hermetic 測試);UI 放 `GlanceApp/Uninstall/`(七狀態 `UninstallViewModel` + `UninstallView`),沿用階段二 `Cleanup` 的 async + 進度回呼 + skippedPaths + 世代/相位守衛樣式。

**Tech Stack:** Swift 5.9、Foundation(GlanceCore)、SwiftUI + AppKit(`NSRunningApplication`,GlanceApp)、XCTest、SwiftPM(`swift test`)、XcodeGen(app 建置)。

**參考規格:** `docs/superpowers/specs/2026-06-16-app-uninstaller-design.md`

**共用既有元件(同模組 GlanceCore,直接可用):**
- `CleanupSizing.size(of:fileManager:)`、`CleanupSizing.isSymbolicLink(_:fileManager:)`(internal,`Sources/GlanceCore/Cleanup/CleanupSizing.swift`)。
- `DiskSpaceSkippedPath`(public,`Sources/GlanceCore/Model/DiskSpaceItem.swift`):`init(url:reason:)`。
- `Formatters.bytes(_:)`(GlanceApp 既用)。

---

## File Structure

**新建(GlanceCore):**
- `Sources/GlanceCore/Uninstall/UninstallModels.swift` — `InstalledApp`、`RelatedFile`、`UninstallPlan`、`UninstallRunResult`、`UninstallProgress`。
- `Sources/GlanceCore/Uninstall/UninstallLocations.swift` — 寫死的 apps 目錄與 `~/Library` 支援目錄。
- `Sources/GlanceCore/Uninstall/UninstallSafety.swift` — 純函式護欄(直接子項 + 正規化前綴 + 非 symlink)。
- `Sources/GlanceCore/Uninstall/AppDiscovery.swift` — 列舉 `.app` 並讀 Info.plist。
- `Sources/GlanceCore/Uninstall/RelatedFileFinder.swift` — bundleID 嚴格比對找關聯檔。
- `Sources/GlanceCore/Uninstall/Uninstaller.swift` — 逐項護欄驗證後移到垃圾桶(移除動作可注入)。

**新建(測試):**
- `Tests/GlanceCoreTests/UninstallSafetyTests.swift`
- `Tests/GlanceCoreTests/AppDiscoveryTests.swift`
- `Tests/GlanceCoreTests/RelatedFileFinderTests.swift`
- `Tests/GlanceCoreTests/UninstallerTests.swift`

**新建(GlanceApp):**
- `GlanceApp/Uninstall/UninstallViewModel.swift`
- `GlanceApp/Uninstall/UninstallView.swift`

**修改(GlanceApp):**
- `GlanceApp/GlanceApp.swift` — 註冊 `Window("解除安裝", id:"uninstall")`。
- `GlanceApp/Dropdown/DropdownView.swift` — footer 新增「解除安裝」按鈕 + `openUninstallWindow()`。

> GlanceCore 測試由 SwiftPM 依目錄自動納入,無需改 `Package.swift`。GlanceApp 由 `project.yml` 的 `sources: [GlanceApp]` 整個目錄取用,新增檔案後需 `xcodegen generate` 重新產生 `Glance.xcodeproj`。

---

## Task 1: 模型(UninstallModels)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/UninstallModels.swift`

無行為、純型別,本任務不寫測試;後續任務會經由它們的使用被覆蓋。

- [ ] **Step 1: 建立模型檔**

```swift
import Foundation

/// 一個使用者安裝的 App。
public struct InstalledApp: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let bundleURL: URL
    public let sizeBytes: UInt64

    public var id: String { bundleID }

    public init(bundleID: String, name: String, bundleURL: URL, sizeBytes: UInt64) {
        self.bundleID = bundleID
        self.name = name
        self.bundleURL = bundleURL
        self.sizeBytes = sizeBytes
    }
}

/// 一個與 App 關聯的散落檔/目錄。
public struct RelatedFile: Equatable, Sendable, Identifiable {
    public let url: URL
    public let sizeBytes: UInt64

    public var id: String { url.path }

    public init(url: URL, sizeBytes: UInt64) {
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

/// 解除安裝計畫:App 本體 + 關聯檔。
public struct UninstallPlan: Equatable, Sendable {
    public let app: InstalledApp
    public let relatedFiles: [RelatedFile]

    public init(app: InstalledApp, relatedFiles: [RelatedFile]) {
        self.app = app
        self.relatedFiles = relatedFiles
    }

    /// 本體 + 全部關聯檔的合計大小。
    public var totalBytes: UInt64 {
        app.sizeBytes + relatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    /// 待處理項目數(本體 1 + 關聯數)。
    public var itemCount: Int { 1 + relatedFiles.count }
}

/// 解除安裝執行結果。
public struct UninstallRunResult: Equatable, Sendable {
    public let trashedCount: Int
    public let freedBytes: UInt64
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(trashedCount: Int, freedBytes: UInt64, skippedPaths: [DiskSpaceSkippedPath]) {
        self.trashedCount = trashedCount
        self.freedBytes = freedBytes
        self.skippedPaths = skippedPaths
    }

    public var skippedCount: Int { skippedPaths.count }
}

/// 執行進度回呼。
public struct UninstallProgress: Equatable, Sendable {
    public let currentPath: String?
    public let trashedCount: Int

    public init(currentPath: String?, trashedCount: Int) {
        self.currentPath = currentPath
        self.trashedCount = trashedCount
    }
}
```

- [ ] **Step 2: 編譯確認**

Run: `swift build`
Expected: 成功(無 error)。

- [ ] **Step 3: Commit**

```bash
git add Sources/GlanceCore/Uninstall/UninstallModels.swift
git commit -m "feat: [core] 新增解除安裝模型 InstalledApp/RelatedFile/UninstallPlan"
```

---

## Task 2: 寫死位置(UninstallLocations)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/UninstallLocations.swift`
- Test: `Tests/GlanceCoreTests/RelatedFileFinderTests.swift`(本任務先放位置測試,檔案於 Task 5 擴充)

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/RelatedFileFinderTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class UninstallLocationsTests: XCTestCase {
    func testAppsDirectoriesAreApplicationsFolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let dirs = UninstallLocations.appsDirectories(home: home).map(\.path)
        XCTAssertEqual(dirs, ["/Applications", "/Users/tester/Applications"])
    }

    func testSupportDirectoriesCoverKnownLibrarySubfolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let dirs = UninstallLocations.supportDirectories(home: home).map(\.path)
        XCTAssertEqual(dirs, [
            "/Users/tester/Library/Application Support",
            "/Users/tester/Library/Caches",
            "/Users/tester/Library/Preferences",
            "/Users/tester/Library/Containers",
            "/Users/tester/Library/Group Containers",
            "/Users/tester/Library/Saved Application State",
            "/Users/tester/Library/Logs",
            "/Users/tester/Library/HTTPStorages",
            "/Users/tester/Library/WebKit",
            "/Users/tester/Library/Cookies",
            "/Users/tester/Library/LaunchAgents",
        ])
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter UninstallLocationsTests`
Expected: FAIL/編譯錯誤(`UninstallLocations` 未定義)。

- [ ] **Step 3: 實作 UninstallLocations**

```swift
import Foundation

/// 解除安裝器掃描/驗證用的寫死位置。
public enum UninstallLocations {
    /// 列舉使用者安裝 App 的目錄。
    public static func appsDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// 可能存放關聯檔的 ~/Library 子目錄。
    public static func supportDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Containers",
            "Library/Group Containers",
            "Library/Saved Application State",
            "Library/Logs",
            "Library/HTTPStorages",
            "Library/WebKit",
            "Library/Cookies",
            "Library/LaunchAgents",
        ].map { home.appendingPathComponent($0, isDirectory: true) }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter UninstallLocationsTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/UninstallLocations.swift Tests/GlanceCoreTests/RelatedFileFinderTests.swift
git commit -m "feat: [core] 新增解除安裝寫死位置 UninstallLocations"
```

---

## Task 3: 安全護欄(UninstallSafety)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/UninstallSafety.swift`
- Test: `Tests/GlanceCoreTests/UninstallSafetyTests.swift`

護欄規則:`.app` 必須是某 apps 目錄的**直接子項**且副檔名為 `.app`;關聯檔必須是某支援目錄的**直接子項**;兩者皆經 `standardizedFileURL` 正規化做嚴格前綴比對、拒絕符號連結、拒絕過淺根、拒絕目錄本身。

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/UninstallSafetyTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class UninstallSafetyTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceUninstallSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    // MARK: App

    func testAppBundleDirectlyUnderAppsDirIsDeletable() throws {
        let apps = try makeTempDir()
        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertTrue(UninstallSafety.isDeletableApp(app, within: [apps]))
    }

    func testNonAppExtensionIsNotDeletableApp() throws {
        let apps = try makeTempDir()
        let notApp = apps.appendingPathComponent("Foo.txt")
        XCTAssertFalse(UninstallSafety.isDeletableApp(notApp, within: [apps]))
    }

    func testNestedAppIsNotDeletableApp() throws {
        // 只允許直接子項;apps/sub/Foo.app 不可。
        let apps = try makeTempDir()
        let nested = apps.appendingPathComponent("sub/Foo.app", isDirectory: true)
        XCTAssertFalse(UninstallSafety.isDeletableApp(nested, within: [apps]))
    }

    func testAppsDirItselfIsNotDeletableApp() throws {
        let apps = try makeTempDir()
        XCTAssertFalse(UninstallSafety.isDeletableApp(apps, within: [apps]))
    }

    func testAppOutsideAppsDirIsNotDeletable() throws {
        let apps = try makeTempDir()
        let outside = try makeTempDir()
        let stray = outside.appendingPathComponent("Foo.app", isDirectory: true)
        XCTAssertFalse(UninstallSafety.isDeletableApp(stray, within: [apps]))
    }

    // MARK: Related

    func testRelatedDirectlyUnderSupportDirIsDeletable() throws {
        let support = try makeTempDir()
        let file = support.appendingPathComponent("com.foo.Bar.plist")
        XCTAssertTrue(UninstallSafety.isDeletableRelated(file, within: [support]))
    }

    func testSupportDirItselfIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        XCTAssertFalse(UninstallSafety.isDeletableRelated(support, within: [support]))
    }

    func testRelatedOutsideSupportDirIsNotDeletable() throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let stray = outside.appendingPathComponent("com.foo.Bar")
        XCTAssertFalse(UninstallSafety.isDeletableRelated(stray, within: [support]))
    }

    func testTraversalEscapeIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        let escape = support.appendingPathComponent("../com.foo.Bar")
        XCTAssertFalse(UninstallSafety.isDeletableRelated(escape, within: [support]))
    }

    func testSymlinkIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let target = outside.appendingPathComponent("real")
        try Data().write(to: target)
        let link = support.appendingPathComponent("com.foo.Bar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertFalse(UninstallSafety.isDeletableRelated(link, within: [support]))
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter UninstallSafetyTests`
Expected: FAIL/編譯錯誤(`UninstallSafety` 未定義)。

- [ ] **Step 3: 實作 UninstallSafety**

```swift
import Foundation

/// 移到垃圾桶前的寫死護欄。`.app` 與關聯檔都必須是某白名單目錄的「直接子項」,
/// 經正規化後以該目錄為嚴格前綴(且不等於目錄本身),拒絕符號連結與過淺根。
public enum UninstallSafety {
    /// `.app` 必須是某 apps 目錄的直接子項、副檔名為 `.app`、非符號連結。
    public static func isDeletableApp(
        _ url: URL,
        within appsDirs: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        guard url.standardizedFileURL.pathExtension == "app" else { return false }
        return isDirectChild(url, of: appsDirs, fileManager: fileManager)
    }

    /// 關聯檔必須是某支援目錄的直接子項、非符號連結。
    public static func isDeletableRelated(
        _ url: URL,
        within supportDirs: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        isDirectChild(url, of: supportDirs, fileManager: fileManager)
    }

    /// 共用:url 是否為某根目錄的「直接子項」(元件數正好多 1、前綴相符、非 symlink)。
    private static func isDirectChild(
        _ url: URL,
        of roots: [URL],
        fileManager: FileManager
    ) -> Bool {
        let standardized = url.standardizedFileURL

        // 拒絕符號連結本身(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        let target = standardized.pathComponents
        for root in roots {
            let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            // 防呆:拒絕過淺的根(如 "/")。
            guard rootComponents.count > 1 else { continue }
            // 直接子項:元件數正好比 root 多 1,且前綴完全等於 root。
            if target.count == rootComponents.count + 1,
               Array(target.prefix(rootComponents.count)) == rootComponents {
                return true
            }
        }
        return false
    }
}
```

> 註:`isDeletableApp` 對 `apps/sub/Foo.app` 會因「元件數多 2」而拒絕(只收直接子項);`../` 遍歷經 `standardizedFileURL` 正規化後落在 root 外,前綴不符而拒絕。

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter UninstallSafetyTests`
Expected: PASS(全 10 例)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/UninstallSafety.swift Tests/GlanceCoreTests/UninstallSafetyTests.swift
git commit -m "feat: [core] 新增解除安裝安全護欄 UninstallSafety"
```

---

## Task 4: App 列舉(AppDiscovery)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/AppDiscovery.swift`
- Test: `Tests/GlanceCoreTests/AppDiscoveryTests.swift`

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/AppDiscoveryTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class AppDiscoveryTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceAppDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    /// 在 appsDir 造一個假 .app:Contents/Info.plist + 一個內容檔(撐出大小)。
    @discardableResult
    private func makeApp(
        in appsDir: URL, fileName: String, bundleID: String?, name: String?, payload: Int = 10
    ) throws -> URL {
        let app = appsDir.appendingPathComponent(fileName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var dict: [String: Any] = [:]
        if let bundleID { dict["CFBundleIdentifier"] = bundleID }
        if let name { dict["CFBundleName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0, count: payload).write(to: contents.appendingPathComponent("blob.bin"))
        return app
    }

    func testDiscoversAppWithBundleIDNameAndSize() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo App", payload: 100)

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertEqual(result.count, 1)
        let app = try XCTUnwrap(result.first)
        XCTAssertEqual(app.bundleID, "com.foo.Bar")
        XCTAssertEqual(app.name, "Foo App")
        XCTAssertGreaterThanOrEqual(app.sizeBytes, 100)
    }

    func testAppWithoutBundleIDIsExcluded() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "NoID.app", bundleID: nil, name: "NoID")

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertTrue(result.isEmpty)
    }

    func testMissingBundleNameFallsBackToFileName() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "Baz.app", bundleID: "com.baz.Qux", name: nil)

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertEqual(result.first?.name, "Baz")
    }

    func testDuplicateBundleIDAcrossDirsIsDeduped() async throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        try makeApp(in: dir1, fileName: "Foo.app", bundleID: "com.dup.App", name: "Foo")
        try makeApp(in: dir2, fileName: "Foo.app", bundleID: "com.dup.App", name: "Foo")

        let result = await AppDiscovery().discover(appsDirectories: [dir1, dir2])
        XCTAssertEqual(result.count, 1)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter AppDiscoveryTests`
Expected: FAIL/編譯錯誤(`AppDiscovery` 未定義)。

- [ ] **Step 3: 實作 AppDiscovery**

```swift
import Foundation

/// async 列舉 apps 目錄直下的 `.app`,讀 Info.plist 取 bundleID/name,算大小。
/// 無 bundleID 者排除;依 bundleID 去重;依名稱排序。
public final class AppDiscovery: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func discover(
        appsDirectories: [URL] = UninstallLocations.appsDirectories()
    ) async -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()

        for dir in appsDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                if Task.isCancelled { return apps }
                if CleanupSizing.isSymbolicLink(entry, fileManager: fileManager) { continue }
                guard let info = Self.readInfo(entry, fileManager: fileManager),
                      let bundleID = info.bundleID, !bundleID.isEmpty,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let size = CleanupSizing.size(of: entry, fileManager: fileManager)
                let name = info.name ?? entry.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    bundleID: bundleID, name: name, bundleURL: entry, sizeBytes: size
                ))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func readInfo(
        _ appURL: URL, fileManager: FileManager
    ) -> (bundleID: String?, name: String?)? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else { return nil }
        let bundleID = plist["CFBundleIdentifier"] as? String
        let name = (plist["CFBundleName"] as? String) ?? (plist["CFBundleDisplayName"] as? String)
        return (bundleID, name)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter AppDiscoveryTests`
Expected: PASS(全 4 例)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/AppDiscovery.swift Tests/GlanceCoreTests/AppDiscoveryTests.swift
git commit -m "feat: [core] 新增 App 列舉 AppDiscovery"
```

---

## Task 5: 關聯檔搜尋(RelatedFileFinder)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/RelatedFileFinder.swift`
- Modify: `Tests/GlanceCoreTests/RelatedFileFinderTests.swift`(追加搜尋測試)

- [ ] **Step 1: 追加失敗測試**

在 `Tests/GlanceCoreTests/RelatedFileFinderTests.swift` 檔尾(`UninstallLocationsTests` 之後)追加:

```swift
final class RelatedFileFinderTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceRelatedFinder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    private func touch(_ url: URL, bytes: Int = 5) throws {
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    func testMatchesExactAndDotPrefixOnly() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("com.foo.Bar"))            // 完全一致
        try touch(support.appendingPathComponent("com.foo.Bar.plist"))      // 點前綴
        try touch(support.appendingPathComponent("com.foo.Bar.savedState")) // 點前綴
        try touch(support.appendingPathComponent("com.foo.BarHelper"))      // 無點延伸 → 不命中
        try touch(support.appendingPathComponent("com.other.App.plist"))    // 別 App → 不命中

        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        let names = Set(found.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.foo.Bar", "com.foo.Bar.plist", "com.foo.Bar.savedState"])
    }

    func testEmptyBundleIDReturnsNothing() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("anything"))
        let found = await RelatedFileFinder().find(bundleID: "", supportDirectories: [support])
        XCTAssertTrue(found.isEmpty)
    }

    func testSymlinkMatchIsSkipped() async throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let target = outside.appendingPathComponent("real")
        try touch(target)
        let link = support.appendingPathComponent("com.foo.Bar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        XCTAssertTrue(found.isEmpty)
    }

    func testComputesSizeForMatchedFile() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("com.foo.Bar.plist"), bytes: 42)
        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        XCTAssertEqual(found.first?.sizeBytes, 42)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter RelatedFileFinderTests`
Expected: FAIL/編譯錯誤(`RelatedFileFinder` 未定義)。

- [ ] **Step 3: 實作 RelatedFileFinder**

```swift
import Foundation

/// 以 bundleID 嚴格比對找關聯檔:檔名 == bundleID 或以 "bundleID." 開頭。
/// 跳過符號連結,並經 UninstallSafety 二次護欄(直接子項)。
public final class RelatedFileFinder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func find(
        bundleID: String,
        supportDirectories: [URL] = UninstallLocations.supportDirectories()
    ) async -> [RelatedFile] {
        guard !bundleID.isEmpty else { return [] }
        let dotPrefix = bundleID + "."
        var files: [RelatedFile] = []

        for dir in supportDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []
            ) else { continue }

            for entry in entries {
                if Task.isCancelled { return files }
                let name = entry.lastPathComponent
                guard name == bundleID || name.hasPrefix(dotPrefix) else { continue }
                if CleanupSizing.isSymbolicLink(entry, fileManager: fileManager) { continue }
                guard UninstallSafety.isDeletableRelated(
                    entry, within: supportDirectories, fileManager: fileManager
                ) else { continue }
                let size = CleanupSizing.size(of: entry, fileManager: fileManager)
                files.append(RelatedFile(url: entry, sizeBytes: size))
            }
        }

        return files
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter RelatedFileFinderTests`
Expected: PASS(`UninstallLocationsTests` 2 例 + `RelatedFileFinderTests` 4 例)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/RelatedFileFinder.swift Tests/GlanceCoreTests/RelatedFileFinderTests.swift
git commit -m "feat: [core] 新增關聯檔搜尋 RelatedFileFinder"
```

---

## Task 6: 移到垃圾桶執行器(Uninstaller)

**Files:**
- Create: `Sources/GlanceCore/Uninstall/Uninstaller.swift`
- Test: `Tests/GlanceCoreTests/UninstallerTests.swift`

移除動作以可注入閉包表示(預設 `FileManager.trashItem`),測試注入「移到 temp 假垃圾桶」以保持 hermetic。

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/UninstallerTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class UninstallerTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceUninstaller-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    private func touch(_ url: URL, bytes: Int) throws {
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    /// 注入式假垃圾桶:把移除動作改成移到 trashDir,讓測試可斷言。
    private func fakeTrash(into trashDir: URL) -> @Sendable (URL) throws -> Void {
        { url in
            let dest = trashDir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
        }
    }

    func testTrashesAppAndRelatedAndReportsFreedBytes() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")
        let trash = try makeTempDir("trash")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try touch(app.appendingPathComponent("blob.bin"), bytes: 100)
        let related = support.appendingPathComponent("com.foo.Bar.plist")
        try touch(related, bytes: 20)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 100),
            relatedFiles: [RelatedFile(url: related, sizeBytes: 20)]
        )
        let uninstaller = Uninstaller(trash: fakeTrash(into: trash))
        let result = await uninstaller.run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 2)
        XCTAssertEqual(result.freedBytes, 120)
        XCTAssertTrue(result.skippedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: related.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Foo.app").path))
    }

    func testMaliciousRelatedOutsideSupportDirIsBlocked() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")
        let outside = try makeTempDir("outside")
        let trash = try makeTempDir("trash")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let evil = outside.appendingPathComponent("com.foo.Bar")  // 範圍外
        try touch(evil, bytes: 10)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 0),
            relatedFiles: [RelatedFile(url: evil, sizeBytes: 10)]
        )
        let result = await Uninstaller(trash: fakeTrash(into: trash)).run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 1)  // 只有 app 本體
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evil.path))  // 惡意項未被動到
    }

    func testTrashFailureGoesToSkippedWithoutAborting() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let related = support.appendingPathComponent("com.foo.Bar.plist")
        try touch(related, bytes: 20)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 0),
            relatedFiles: [RelatedFile(url: related, sizeBytes: 20)]
        )
        // 對 app 本體拋錯、其餘成功:驗證不中斷且失敗進 skipped。
        let failingTrash: @Sendable (URL) throws -> Void = { url in
            if url.pathExtension == "app" {
                throw NSError(domain: "test", code: 1)
            }
            try FileManager.default.removeItem(at: url)
        }
        let result = await Uninstaller(trash: failingTrash).run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 1)  // related 成功
        XCTAssertEqual(result.skippedCount, 1)  // app 失敗
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter UninstallerTests`
Expected: FAIL/編譯錯誤(`Uninstaller` 未定義)。

- [ ] **Step 3: 實作 Uninstaller**

```swift
import Foundation

/// 收 UninstallPlan,逐項先過 UninstallSafety,再以可注入的移除動作(預設移到垃圾桶)處理。
/// app 本體用 isDeletableApp 護欄、關聯檔用 isDeletableRelated;符號連結或失敗進 skipped,不中斷。
///
/// 安全性不變式:無可變儲存屬性(只有 let),run() 累加狀態皆為函式內區域變數,故 @unchecked Sendable 安全。
public final class Uninstaller: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (UninstallProgress) async -> Void
    public typealias TrashAction = @Sendable (URL) throws -> Void

    private let fileManager: FileManager
    private let trash: TrashAction

    public init(fileManager: FileManager = .default, trash: TrashAction? = nil) {
        self.fileManager = fileManager
        self.trash = trash ?? { url in
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    public func run(
        plan: UninstallPlan,
        appsDirectories: [URL] = UninstallLocations.appsDirectories(),
        supportDirectories: [URL] = UninstallLocations.supportDirectories(),
        progress: ProgressHandler? = nil
    ) async -> UninstallRunResult {
        var freed: UInt64 = 0
        var trashed = 0
        var skipped: [DiskSpaceSkippedPath] = []

        // 待處理清單:本體在前(用 app 護欄),其餘關聯檔(用 related 護欄)。
        let appURL = plan.app.bundleURL
        var items: [(url: URL, size: UInt64, isApp: Bool)] =
            [(appURL, plan.app.sizeBytes, true)]
        items += plan.relatedFiles.map { ($0.url, $0.sizeBytes, false) }

        for item in items {
            if Task.isCancelled { break }

            if CleanupSizing.isSymbolicLink(item.url, fileManager: fileManager) {
                skipped.append(DiskSpaceSkippedPath(url: item.url, reason: "Symbolic link skipped"))
                continue
            }

            let allowed = item.isApp
                ? UninstallSafety.isDeletableApp(item.url, within: appsDirectories, fileManager: fileManager)
                : UninstallSafety.isDeletableRelated(item.url, within: supportDirectories, fileManager: fileManager)
            guard allowed else {
                skipped.append(DiskSpaceSkippedPath(url: item.url, reason: "Blocked by safety guard"))
                continue
            }

            do {
                try trash(item.url)
                freed += item.size
                trashed += 1
                if let progress {
                    await progress(UninstallProgress(currentPath: item.url.path, trashedCount: trashed))
                }
            } catch {
                skipped.append(DiskSpaceSkippedPath(
                    url: item.url, reason: "Trash failed: \(error.localizedDescription)"
                ))
            }
        }

        return UninstallRunResult(trashedCount: trashed, freedBytes: freed, skippedPaths: skipped)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter UninstallerTests`
Expected: PASS(全 3 例)。

- [ ] **Step 5: 跑全部 GlanceCore 測試確認無回歸**

Run: `swift test`
Expected: 全綠(原 107 + 新增約 23 例)。

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/Uninstall/Uninstaller.swift Tests/GlanceCoreTests/UninstallerTests.swift
git commit -m "feat: [core] 新增解除安裝執行器 Uninstaller(可注入移除動作)"
```

---

## Task 7: ViewModel(UninstallViewModel)

**Files:**
- Create: `GlanceApp/Uninstall/UninstallViewModel.swift`

GlanceApp 無 test target(同 `CleanupViewModel`),本任務不寫單元測試,改於 Task 9 實機驗證。沿用 `CleanupViewModel` 的世代防護 + 相位守衛。

- [ ] **Step 1: 建立 ViewModel**

```swift
import AppKit
import Combine
import Foundation
import GlanceCore

@MainActor
final class UninstallViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading      // 掃描 App 一覽
        case list         // 選擇 App
        case building     // 構建計畫(找關聯檔 + 執行中檢查)
        case preview      // 預覽計畫
        case confirming   // 確認 sheet
        case running      // 移到垃圾桶中
        case done         // 完成
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var apps: [InstalledApp] = []
    @Published var searchText: String = ""
    @Published private(set) var plan: UninstallPlan?
    @Published private(set) var selectedAppRunning = false
    @Published private(set) var currentPath: String?
    @Published private(set) var runResult: UninstallRunResult?

    private let discovery: AppDiscovery
    private let finder: RelatedFileFinder
    private let uninstaller: Uninstaller
    private let isRunning: @Sendable (String) -> Bool

    private var loadTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var generation = 0

    init(
        discovery: AppDiscovery = AppDiscovery(),
        finder: RelatedFileFinder = RelatedFileFinder(),
        uninstaller: Uninstaller = Uninstaller(),
        isRunning: @escaping @Sendable (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    ) {
        self.discovery = discovery
        self.finder = finder
        self.uninstaller = uninstaller
        self.isRunning = isRunning
    }

    deinit {
        loadTask?.cancel()
        buildTask?.cancel()
        runTask?.cancel()
    }

    // MARK: Derived

    var filteredApps: [InstalledApp] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var canUninstall: Bool { phase == .preview && !selectedAppRunning }

    // MARK: Actions

    func load() {
        loadTask?.cancel()
        generation += 1
        let generation = generation
        phase = .loading
        apps = []
        loadTask = Task { [weak self, discovery] in
            let result = await discovery.discover()
            await self?.applyApps(result, generation: generation)
        }
    }

    func select(_ app: InstalledApp) {
        buildTask?.cancel()
        generation += 1
        let generation = generation
        phase = .building
        plan = nil
        currentPath = nil
        buildTask = Task { [weak self, finder, isRunning] in
            let related = await finder.find(bundleID: app.bundleID)
            let running = isRunning(app.bundleID)
            let plan = UninstallPlan(app: app, relatedFiles: related)
            await self?.applyPlan(plan, running: running, generation: generation)
        }
    }

    func backToList() {
        guard phase == .preview || phase == .done else { return }
        buildTask?.cancel()
        runTask?.cancel()
        generation += 1
        plan = nil
        runResult = nil
        currentPath = nil
        selectedAppRunning = false
        phase = .list
    }

    func requestConfirmation() {
        guard phase == .preview, !selectedAppRunning else { return }
        phase = .confirming
    }

    func cancelConfirmation() {
        guard phase == .confirming else { return }
        phase = .preview
    }

    func confirmUninstall() {
        guard phase == .confirming, let plan else { return }
        runTask?.cancel()
        generation += 1
        let generation = generation
        phase = .running
        currentPath = nil
        runTask = Task { [weak self, uninstaller] in
            let result = await uninstaller.run(plan: plan) { [weak self] progress in
                await self?.applyRunProgress(progress, generation: generation)
            }
            await self?.applyRunResult(result, generation: generation)
        }
    }

    // MARK: Apply (MainActor)

    private func applyApps(_ result: [InstalledApp], generation: Int) {
        guard generation == self.generation else { return }
        apps = result
        phase = .list
        loadTask = nil
    }

    private func applyPlan(_ plan: UninstallPlan, running: Bool, generation: Int) {
        guard generation == self.generation else { return }
        self.plan = plan
        selectedAppRunning = running
        phase = .preview
        buildTask = nil
    }

    private func applyRunProgress(_ progress: UninstallProgress, generation: Int) {
        guard generation == self.generation, phase == .running else { return }
        currentPath = progress.currentPath
    }

    private func applyRunResult(_ result: UninstallRunResult, generation: Int) {
        guard generation == self.generation else { return }
        runResult = result
        currentPath = nil
        phase = .done
        runTask = nil
    }
}
```

- [ ] **Step 2: 編譯確認(透過 Task 8 一併建置;此步先確認語法)**

Run: `swift build`
Expected: 成功(`swift build` 只建 GlanceCore；本檔屬 GlanceApp,語法錯誤需待 Task 8 的 xcodebuild 才會抓到。此處僅確認 GlanceCore 仍綠)。

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/Uninstall/UninstallViewModel.swift
git commit -m "feat: [app] 新增解除安裝 ViewModel 七狀態機"
```

---

## Task 8: View 與接線(UninstallView + 視窗 + footer)

**Files:**
- Create: `GlanceApp/Uninstall/UninstallView.swift`
- Modify: `GlanceApp/GlanceApp.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1: 建立 UninstallView**

```swift
import SwiftUI
import GlanceCore

struct UninstallView: View {
    @StateObject private var viewModel = UninstallViewModel()
    @Environment(\.dismiss) private var dismiss

    private let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
        .sheet(isPresented: confirmBinding) { confirmationSheet }
        .onAppear {
            if viewModel.phase == .loading, viewModel.apps.isEmpty {
                viewModel.load()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解除安裝")
                .font(.system(size: 20, weight: .semibold))
            Text("選擇 App,連帶移除其關聯檔。本體與關聯檔會移到垃圾桶,可從垃圾桶復原。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            centeredProgress("讀取 App 一覽…")
        case .list:
            listView
        case .building:
            centeredProgress("分析關聯檔…")
        case .preview, .confirming:
            previewView
        case .running:
            centeredProgress("移到垃圾桶…", path: viewModel.currentPath)
        case .done:
            doneView
        }
    }

    private func centeredProgress(_ title: String, path: String? = nil) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).font(.system(size: 13))
            if let path {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var listView: some View {
        VStack(spacing: 10) {
            TextField("搜尋 App", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            List(viewModel.filteredApps) { app in
                Button {
                    viewModel.select(app)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.bundleID)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Text(Formatters.bytes(app.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Preview

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = viewModel.plan {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.app.name).font(.system(size: 15, weight: .semibold))
                        Text(plan.app.bundleID)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatters.bytes(plan.totalBytes))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if viewModel.selectedAppRunning {
                    Label("此 App 執行中,請先結束後再解除安裝。", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }

                List {
                    Section("本體") {
                        row(path: plan.app.bundleURL.path, bytes: plan.app.sizeBytes)
                    }
                    Section("關聯檔(\(plan.relatedFiles.count))") {
                        if plan.relatedFiles.isEmpty {
                            Text("無").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.relatedFiles) { file in
                                row(path: file.url.path, bytes: file.sizeBytes)
                            }
                        }
                    }
                }

                HStack {
                    Button("返回") { viewModel.backToList() }
                    Spacer()
                    Button("移到垃圾桶…") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canUninstall)
                }
            }
        }
    }

    private func row(path: String, bytes: UInt64) -> some View {
        HStack {
            Text(path.replacingOccurrences(of: homePath, with: "~"))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(Formatters.bytes(bytes))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Confirmation sheet

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirming },
            set: { if !$0 { viewModel.cancelConfirmation() } }
        )
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("解除安裝", systemImage: "trash.fill")
                .font(.system(size: 16, weight: .semibold))

            if let plan = viewModel.plan {
                Text("將把「\(plan.app.name)」本體與關聯 \(plan.relatedFiles.count) 件(合計約 \(Formatters.bytes(plan.totalBytes)))移到垃圾桶。可從垃圾桶復原。")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { viewModel.cancelConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Button("移到垃圾桶") { viewModel.confirmUninstall() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.18), lineWidth: 10)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text(Formatters.bytes(viewModel.runResult?.freedBytes ?? 0))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已釋放").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text("移到垃圾桶 \(viewModel.runResult?.trashedCount ?? 0) 項 · 跳過 \(viewModel.runResult?.skippedCount ?? 0) 項(無權限)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("繼續解除安裝") { viewModel.backToList() }
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: 註冊視窗** — 修改 `GlanceApp/GlanceApp.swift`,在 `Window("清理", id: "cleanup") { CleanupView() }` 之後加入:

```swift
        Window("解除安裝", id: "uninstall") {
            UninstallView()
        }
```

- [ ] **Step 3: footer 加按鈕** — 修改 `GlanceApp/Dropdown/DropdownView.swift`。在「清理」按鈕的 `}` `.buttonStyle(.plain)` `.foregroundStyle(.secondary)` 區塊之後(`Spacer()` 之前)插入:

```swift
            Button {
                openUninstallWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 11, weight: .medium))
                    Text("解除安裝")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
```

- [ ] **Step 4: 加開窗函式** — 在 `DropdownView.swift` 的 `openCleanupWindow()` 之後加入:

```swift
    private func openUninstallWindow() {
        openWindow(id: "uninstall")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
```

- [ ] **Step 5: 重新產生 xcodeproj 並建置**

Run:
```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: Commit**

```bash
git add GlanceApp/Uninstall/UninstallView.swift GlanceApp/GlanceApp.swift GlanceApp/Dropdown/DropdownView.swift Glance.xcodeproj
git commit -m "feat: [app] 新增解除安裝視窗 UninstallView 並接線 footer/視窗"
```

---

## Task 9: 實機驗證(依 verify-by-launching-app 記憶)

**Files:** 無(手動驗證)

- [ ] **Step 1: 全測試最終確認**

Run: `swift test`
Expected: 全綠(原 107 + 新增約 23 例,0 failures)。

- [ ] **Step 2: 啟動 app**

Run:
```bash
swift build  # 確認核心無誤
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/Glance.app
```
Expected: 選單列出現 Glance 圖示,不閃退。

- [ ] **Step 3: 手動驗收(使用者親自,破壞性步驟自行決定)**

確認:
- 下拉 footer 出現「解除安裝」鈕,點開開窗。
- 一覽列出 `/Applications` 與 `~/Applications` 的 App、大小合理、搜尋可過濾。
- 點一個 App → 預覽顯示本體 + 關聯檔清單 + 合計;若該 App 執行中,顯示橙色警告且「移到垃圾桶」鈕停用。
- (可選,破壞性)對一個用後即丟的測試 App 實際解除安裝 → 確認回收量、跳過顯示、垃圾桶內可見本體與關聯檔、不崩;能從垃圾桶復原。

- [ ] **Step 4: 更新路線圖記憶**

把 `~/.claude/projects/-Users-carl-Dev-Carl-Glance/memory/mole-inspired-roadmap.md` 的階段三標記為完成,並記下 spec/plan 路徑與已知 fast-follow(`UninstallViewModel` 無單元測試、實機破壞性驗收留給使用者)。

---

## Self-Review 對照

- **spec 對象範圍(A)** → Task 2 `UninstallLocations.appsDirectories` 僅 `/Applications` + `~/Applications`;Task 4 列舉。✅
- **刪除方式=垃圾桶(A)** → Task 6 `Uninstaller` 預設 `FileManager.trashItem`,可注入。✅
- **Bundle ID 嚴格比對(A)** → Task 5 `name == bundleID || hasPrefix(bundleID + ".")`,`BarHelper` 不命中(測試覆蓋)。✅
- **執行中阻擋(A)** → Task 7 `isRunning` 注入 + `selectedAppRunning`;Task 8 橙色警告 + `canUninstall` 停用。✅
- **一括(A)** → Task 8 預覽為唯讀清單,無逐檔勾選;`Uninstaller.run` 收整個 plan。✅
- **安全護欄** → Task 3 直接子項 + 正規化前綴 + 非 symlink + 過淺根防呆;Task 6 刪前雙重驗證。✅
- **skippedPaths 不中斷** → Task 6 失敗/被擋進 skipped,迴圈續行(測試覆蓋)。✅
- **型別一致性** → `InstalledApp`/`RelatedFile`/`UninstallPlan`/`UninstallRunResult`/`UninstallProgress` 全程命名一致;`Uninstaller.run(plan:appsDirectories:supportDirectories:progress:)` 與 ViewModel 呼叫(用預設參數)一致。✅
- **測試與驗收** → Task 3–6 單元測試;Task 9 實機驗證。✅
- **fast-follow** → Task 9 記憶更新記錄 ViewModel 無測試、破壞性驗收。✅
