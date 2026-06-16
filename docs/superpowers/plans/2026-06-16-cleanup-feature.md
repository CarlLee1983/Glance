# 清理功能(階段二)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Glance 能掃描、預覽、明確確認後**永久刪除**三類可回收空間(垃圾桶、使用者快取與日誌、開發工具快取),以寫死安全護欄 + 完整單元測試把關破壞性刪除。

**Architecture:** 純邏輯(類別定義、安全護欄、掃描、刪除)放 `GlanceCore/Cleanup/`,沿用既有 `DiskSpaceAnalyzer` 的 async + 進度回呼 + `DiskSpaceSkippedPath` 風格;UI(單一視窗五狀態的狀態機)放 `GlanceApp/Cleanup/`,以新 `Window` 開窗、從下拉 footer 觸發,比照既有 `DiskSpaceAnalyzerWindow`。

**Tech Stack:** Swift 5.9、SwiftPM、Foundation `FileManager`、SwiftUI / AppKit、XCTest(臨時目錄)。macOS 14+。

---

## File Structure

**GlanceCore — `Sources/GlanceCore/Cleanup/`(純邏輯,可測):**
- `CleanupCategory.swift` — `CleanupCategoryID` enum、`CleanupCategory` struct、`defaults(home:)` 內建三類與寫死路徑。
- `CleanupResults.swift` — `CleanupCategoryResult`、`CleanupCategoryRunResult`、`CleanupRunResult`、`CleanupScanProgress`、`CleanupRunProgress` 等資料模型。
- `CleanupSizing.swift` — 內部遞迴大小計算與符號連結判斷,scanner/executor 共用(DRY)。
- `CleanupSafety.swift` — 純函式護欄 `isDeletable(_:within:)`(最該獨立測)。
- `CleanupScanner.swift` — async 掃描各類別根目錄,算可回收 bytes + 項目數。
- `CleanupExecutor.swift` — 收勾選類別,刪根目錄底下內容物,刪每個路徑前用 `CleanupSafety` 驗證。

**GlanceApp — `GlanceApp/Cleanup/`(UI):**
- `CleanupViewModel.swift` — `@MainActor ObservableObject`,串接 scanner/executor 與五狀態機。
- `CleanupView.swift` — 視窗內容;掃描中 → 勾選 → 確認 sheet → 執行中 → 完成。

**既有檔修改:**
- `GlanceApp/GlanceApp.swift` — 註冊 `Window("清理", id: "cleanup")`。
- `GlanceApp/Dropdown/DropdownView.swift` — footer 新增「清理…」按鈕開窗。

**測試 — `Tests/GlanceCoreTests/`:**
- `CleanupSafetyTests.swift`、`CleanupScannerTests.swift`、`CleanupExecutorTests.swift`。

---

## Task 1: Cleanup 資料模型與類別定義

**Files:**
- Create: `Sources/GlanceCore/Cleanup/CleanupCategory.swift`
- Create: `Sources/GlanceCore/Cleanup/CleanupResults.swift`
- Test: `Tests/GlanceCoreTests/CleanupSafetyTests.swift`(本任務先放一個 defaults 測試,Task 2 再擴充)

- [ ] **Step 1: 寫失敗測試(defaults 內建三類與路徑)**

Create `Tests/GlanceCoreTests/CleanupSafetyTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class CleanupCategoryTests: XCTestCase {
    func testDefaultsProvideThreeCategoriesWithExpectedRoots() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let categories = CleanupCategory.defaults(home: home)

        XCTAssertEqual(categories.map(\.id), [.trash, .userCaches, .devCaches])

        let trash = try? XCTUnwrap(categories.first { $0.id == .trash })
        XCTAssertEqual(trash??.roots.map(\.path), ["/Users/tester/.Trash"])

        let userCaches = categories.first { $0.id == .userCaches }
        XCTAssertEqual(userCaches?.roots.map(\.path),
                       ["/Users/tester/Library/Caches", "/Users/tester/Library/Logs"])

        let devCaches = categories.first { $0.id == .devCaches }
        XCTAssertEqual(devCaches?.roots.map(\.path),
                       ["/Users/tester/Library/Developer/Xcode/DerivedData",
                        "/Users/tester/.npm",
                        "/Users/tester/.cache"])
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CleanupCategoryTests`
Expected: 編譯失敗 — `cannot find 'CleanupCategory' in scope`。

- [ ] **Step 3: 建立 `CleanupResults.swift`**

```swift
import Foundation

/// 掃描各類別後的可回收量估算。
public struct CleanupCategoryResult: Equatable, Sendable, Identifiable {
    public let id: CleanupCategoryID
    public let reclaimableBytes: UInt64
    public let itemCount: Int

    public init(id: CleanupCategoryID, reclaimableBytes: UInt64, itemCount: Int) {
        self.id = id
        self.reclaimableBytes = reclaimableBytes
        self.itemCount = itemCount
    }
}

/// 單一類別實際刪除後的結果。
public struct CleanupCategoryRunResult: Equatable, Sendable, Identifiable {
    public let id: CleanupCategoryID
    public let reclaimedBytes: UInt64
    public let deletedCount: Int

    public init(id: CleanupCategoryID, reclaimedBytes: UInt64, deletedCount: Int) {
        self.id = id
        self.reclaimedBytes = reclaimedBytes
        self.deletedCount = deletedCount
    }
}

/// 整批清理結果:各類別結果 + 跳過清單(沿用既有 DiskSpaceSkippedPath)。
public struct CleanupRunResult: Equatable, Sendable {
    public let categories: [CleanupCategoryRunResult]
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(categories: [CleanupCategoryRunResult], skippedPaths: [DiskSpaceSkippedPath]) {
        self.categories = categories
        self.skippedPaths = skippedPaths
    }

    public var totalReclaimedBytes: UInt64 { categories.reduce(0) { $0 + $1.reclaimedBytes } }
    public var totalDeletedCount: Int { categories.reduce(0) { $0 + $1.deletedCount } }
    public var skippedCount: Int { skippedPaths.count }
}

/// 掃描進度回呼。
public struct CleanupScanProgress: Equatable, Sendable {
    public let categoryID: CleanupCategoryID
    public let currentPath: String?

    public init(categoryID: CleanupCategoryID, currentPath: String?) {
        self.categoryID = categoryID
        self.currentPath = currentPath
    }
}

/// 刪除進度回呼。
public struct CleanupRunProgress: Equatable, Sendable {
    public let categoryID: CleanupCategoryID
    public let currentPath: String?
    public let deletedCount: Int

    public init(categoryID: CleanupCategoryID, currentPath: String?, deletedCount: Int) {
        self.categoryID = categoryID
        self.currentPath = currentPath
        self.deletedCount = deletedCount
    }
}
```

- [ ] **Step 4: 建立 `CleanupCategory.swift`**

```swift
import Foundation

public enum CleanupCategoryID: String, CaseIterable, Sendable {
    case trash
    case userCaches
    case devCaches
}

/// 一個清理類別:顯示名稱 + 白名單根目錄(已展開 ~)。
public struct CleanupCategory: Equatable, Sendable, Identifiable {
    public let id: CleanupCategoryID
    public let displayName: String
    public let roots: [URL]

    public init(id: CleanupCategoryID, displayName: String, roots: [URL]) {
        self.id = id
        self.displayName = displayName
        self.roots = roots
    }

    /// 內建三類與寫死路徑。根目錄互不重疊,避免重複計算。
    public static func defaults(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [CleanupCategory] {
        func sub(_ path: String) -> URL { home.appendingPathComponent(path) }
        return [
            CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [sub(".Trash")]),
            CleanupCategory(
                id: .userCaches,
                displayName: "使用者快取與日誌",
                roots: [sub("Library/Caches"), sub("Library/Logs")]
            ),
            CleanupCategory(
                id: .devCaches,
                displayName: "開發工具快取",
                roots: [
                    sub("Library/Developer/Xcode/DerivedData"),
                    sub(".npm"),
                    sub(".cache"),
                ]
            ),
        ]
    }
}
```

- [ ] **Step 5: 跑測試確認通過**

Run: `swift test --filter CleanupCategoryTests`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/Cleanup/CleanupCategory.swift Sources/GlanceCore/Cleanup/CleanupResults.swift Tests/GlanceCoreTests/CleanupSafetyTests.swift
git commit -m "feat: [core] 新增清理類別定義與結果模型"
```

---

## Task 2: 安全護欄 `CleanupSafety.isDeletable`

**Files:**
- Create: `Sources/GlanceCore/Cleanup/CleanupSafety.swift`
- Test: `Tests/GlanceCoreTests/CleanupSafetyTests.swift`(同 Task 1 檔案,新增 class)

- [ ] **Step 1: 寫失敗測試(五種護欄情境)**

在 `Tests/GlanceCoreTests/CleanupSafetyTests.swift` 檔尾新增:

```swift
final class CleanupSafetyTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testChildUnderRootIsDeletable() throws {
        let root = try makeTempRoot()
        let child = root.appendingPathComponent("cache.dat")
        XCTAssertTrue(CleanupSafety.isDeletable(child, within: [root]))
    }

    func testRootItselfIsNotDeletable() throws {
        let root = try makeTempRoot()
        XCTAssertFalse(CleanupSafety.isDeletable(root, within: [root]))
    }

    func testPathOutsideRootIsNotDeletable() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let stray = outside.appendingPathComponent("doc.txt")
        XCTAssertFalse(CleanupSafety.isDeletable(stray, within: [root]))
    }

    func testSiblingWithSharedPrefixIsNotDeletable() throws {
        // root 為 ".../Caches";".../Caches2/x" 不該被誤判為在 root 底下。
        let base = try makeTempRoot()
        let root = base.appendingPathComponent("Caches", isDirectory: true)
        let sibling = base.appendingPathComponent("Caches2/x")
        XCTAssertFalse(CleanupSafety.isDeletable(sibling, within: [root]))
    }

    func testParentTraversalIsNotDeletable() throws {
        let root = try makeTempRoot()
        let escaping = root.appendingPathComponent("../escape.dat")
        XCTAssertFalse(CleanupSafety.isDeletable(escaping, within: [root]))
    }

    func testSymbolicLinkIsNotDeletable() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(CleanupSafety.isDeletable(link, within: [root]))
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CleanupSafetyTests`
Expected: 編譯失敗 — `cannot find 'CleanupSafety' in scope`。

- [ ] **Step 3: 實作 `CleanupSafety.swift`**

```swift
import Foundation

/// 永久刪除前的寫死護欄:只允許刪白名單根目錄「底下」的內容物。
/// 以正規化後的 pathComponents 做嚴格前綴比對,可擋 `../` 路徑遍歷與
/// 共享前綴(Caches vs Caches2)的誤判;符號連結一律拒絕。
public enum CleanupSafety {
    public static func isDeletable(
        _ url: URL,
        within roots: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        let target = url.standardizedFileURL

        // 拒絕符號連結(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        let targetComponents = target.pathComponents
        for root in roots {
            let rootComponents = root.standardizedFileURL.pathComponents
            // 必須是 root 的嚴格後代:元件數更多,且前綴完全等於 root。
            if targetComponents.count > rootComponents.count,
               Array(targetComponents.prefix(rootComponents.count)) == rootComponents {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CleanupSafetyTests`
Expected: PASS(6 個案例全綠)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Cleanup/CleanupSafety.swift Tests/GlanceCoreTests/CleanupSafetyTests.swift
git commit -m "feat: [core] 新增清理安全護欄 CleanupSafety.isDeletable"
```

---

## Task 3: 共用大小計算 `CleanupSizing`

**Files:**
- Create: `Sources/GlanceCore/Cleanup/CleanupSizing.swift`
- Test: `Tests/GlanceCoreTests/CleanupScannerTests.swift`(本任務先放 sizing 測試,Task 4 擴充 scanner)

- [ ] **Step 1: 寫失敗測試(遞迴大小、跳符號連結)**

Create `Tests/GlanceCoreTests/CleanupScannerTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class CleanupSizingTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testSizeSumsNestedFiles() throws {
        let root = try makeTempRoot()
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("a/one.dat"), byteCount: 10)
        try writeFile(nested.appendingPathComponent("two.dat"), byteCount: 25)

        XCTAssertEqual(CleanupSizing.size(of: root.appendingPathComponent("a"), fileManager: .default), 35)
    }

    func testSizeIgnoresSymbolicLinks() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeFile(outside.appendingPathComponent("big.dat"), byteCount: 999)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertEqual(CleanupSizing.size(of: link, fileManager: .default), 0)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupSizingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CleanupSizingTests`
Expected: 編譯失敗 — `cannot find 'CleanupSizing' in scope`。

- [ ] **Step 3: 實作 `CleanupSizing.swift`**

```swift
import Foundation

/// scanner / executor 共用的遞迴大小計算與符號連結判斷。internal,僅供模組內使用。
enum CleanupSizing {
    static func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// 遞迴計算 url 佔用位元組;符號連結回 0(不跟隨);不可讀目錄回 0。
    static func size(of url: URL, fileManager: FileManager) -> UInt64 {
        if isSymbolicLink(url, fileManager: fileManager) { return 0 }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(values?.fileSize ?? 0)
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        ) else { return 0 }

        var total: UInt64 = 0
        for child in children {
            total += size(of: child, fileManager: fileManager)
        }
        return total
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CleanupSizingTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Cleanup/CleanupSizing.swift Tests/GlanceCoreTests/CleanupScannerTests.swift
git commit -m "feat: [core] 新增共用遞迴大小計算 CleanupSizing"
```

---

## Task 4: 掃描器 `CleanupScanner`

**Files:**
- Create: `Sources/GlanceCore/Cleanup/CleanupScanner.swift`
- Test: `Tests/GlanceCoreTests/CleanupScannerTests.swift`(同 Task 3 檔案,新增 class)

- [ ] **Step 1: 寫失敗測試(各類別 bytes/項目數、跳符號連結)**

在 `Tests/GlanceCoreTests/CleanupScannerTests.swift` 檔尾新增:

```swift
final class CleanupScannerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testScanReportsBytesAndItemCountPerCategory() async throws {
        let trashRoot = try makeTempRoot()
        try writeFile(trashRoot.appendingPathComponent("junk1.dat"), byteCount: 100)
        try writeFile(trashRoot.appendingPathComponent("junk2.dat"), byteCount: 50)

        let cacheRoot = try makeTempRoot()
        let nested = cacheRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(nested.appendingPathComponent("c.dat"), byteCount: 30)

        let categories = [
            CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [trashRoot]),
            CleanupCategory(id: .userCaches, displayName: "使用者快取與日誌", roots: [cacheRoot]),
        ]

        let results = await CleanupScanner().scan(categories: categories)

        let trash = try XCTUnwrap(results.first { $0.id == .trash })
        XCTAssertEqual(trash.reclaimableBytes, 150)
        XCTAssertEqual(trash.itemCount, 2)

        let caches = try XCTUnwrap(results.first { $0.id == .userCaches })
        XCTAssertEqual(caches.reclaimableBytes, 30)
        XCTAssertEqual(caches.itemCount, 1) // "app" 目錄算一項
    }

    func testScanSkipsSymbolicLinks() async throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeFile(outside.appendingPathComponent("big.dat"), byteCount: 500)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try writeFile(root.appendingPathComponent("real.dat"), byteCount: 20)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let results = await CleanupScanner().scan(categories: categories)

        let trash = try XCTUnwrap(results.first)
        XCTAssertEqual(trash.reclaimableBytes, 20) // 不含 symlink 指向的 500
        XCTAssertEqual(trash.itemCount, 1)         // symlink 不計入
    }

    func testMissingRootContributesZero() async throws {
        let root = try makeTempRoot()
        try FileManager.default.removeItem(at: root) // 不存在

        let categories = [CleanupCategory(id: .devCaches, displayName: "開發工具快取", roots: [root])]
        let results = await CleanupScanner().scan(categories: categories)

        let dev = try XCTUnwrap(results.first)
        XCTAssertEqual(dev.reclaimableBytes, 0)
        XCTAssertEqual(dev.itemCount, 0)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CleanupScannerTests`
Expected: 編譯失敗 — `cannot find 'CleanupScanner' in scope`。

- [ ] **Step 3: 實作 `CleanupScanner.swift`**

```swift
import Foundation

/// 掃描各類別根目錄,計算可回收 bytes + 頂層項目數。只看根目錄底下的直接子項,
/// 跳過符號連結;不可讀的根目錄略過、貢獻 0(沿用既有掃描器寬容作法)。
public final class CleanupScanner: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (CleanupScanProgress) async -> Void

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(
        categories: [CleanupCategory],
        progress: ProgressHandler? = nil
    ) async -> [CleanupCategoryResult] {
        var results: [CleanupCategoryResult] = []

        for category in categories {
            if Task.isCancelled { break }
            var reclaimable: UInt64 = 0
            var itemCount = 0

            for root in category.roots {
                guard let children = try? fileManager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                ) else { continue }

                for child in children {
                    if Task.isCancelled { break }
                    if CleanupSizing.isSymbolicLink(child, fileManager: fileManager) { continue }
                    itemCount += 1
                    reclaimable += CleanupSizing.size(of: child, fileManager: fileManager)
                    if let progress {
                        await progress(CleanupScanProgress(categoryID: category.id, currentPath: child.path))
                    }
                }
            }

            results.append(CleanupCategoryResult(
                id: category.id, reclaimableBytes: reclaimable, itemCount: itemCount
            ))
        }

        return results
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CleanupScannerTests`
Expected: PASS(3 個案例)。

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Cleanup/CleanupScanner.swift Tests/GlanceCoreTests/CleanupScannerTests.swift
git commit -m "feat: [core] 新增清理掃描器 CleanupScanner"
```

---

## Task 5: 刪除執行器 `CleanupExecutor`

**Files:**
- Create: `Sources/GlanceCore/Cleanup/CleanupExecutor.swift`
- Test: `Tests/GlanceCoreTests/CleanupExecutorTests.swift`

- [ ] **Step 1: 寫失敗測試(刪內容物保留根、回收量、護欄擋惡意項)**

Create `Tests/GlanceCoreTests/CleanupExecutorTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class CleanupExecutorTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testDeletesContentsButKeepsRoot() async throws {
        let root = try makeTempRoot()
        try writeFile(root.appendingPathComponent("a.dat"), byteCount: 100)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try writeFile(sub.appendingPathComponent("b.dat"), byteCount: 50)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path)) // 根目錄保留
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(remaining.isEmpty)                                  // 內容物清空

        let trash = try XCTUnwrap(result.categories.first { $0.id == .trash })
        XCTAssertEqual(trash.reclaimedBytes, 150)
        XCTAssertEqual(trash.deletedCount, 2)
        XCTAssertTrue(result.skippedPaths.isEmpty)
    }

    func testSymlinkChildIsSkippedAndTargetSurvives() async throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let sentinel = outside.appendingPathComponent("keep.dat")
        try writeFile(sentinel, byteCount: 42)
        let link = root.appendingPathComponent("evil-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try writeFile(root.appendingPathComponent("real.dat"), byteCount: 10)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        // 護欄:symlink 指向的外部 sentinel 必須存活,不被跟隨刪除。
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let trash = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(trash.deletedCount, 1)                 // 只刪 real.dat
        XCTAssertEqual(trash.reclaimedBytes, 10)
        XCTAssertEqual(result.skippedPaths.count, 1)          // symlink 進 skipped
        XCTAssertEqual(result.skippedPaths.first?.url, link)
    }

    func testEmptyCategoryYieldsZeroResult() async throws {
        let root = try makeTempRoot()
        let categories = [CleanupCategory(id: .userCaches, displayName: "使用者快取與日誌", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        let caches = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(caches.deletedCount, 0)
        XCTAssertEqual(caches.reclaimedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CleanupExecutorTests`
Expected: 編譯失敗 — `cannot find 'CleanupExecutor' in scope`。

- [ ] **Step 3: 實作 `CleanupExecutor.swift`**

```swift
import Foundation

/// 收使用者勾選的類別,刪除其根目錄底下的內容物。刪每個路徑前:
/// 跳過符號連結、再經 CleanupSafety 驗證;失敗/被擋的路徑進 skippedPaths 不中斷整批。
/// 永不刪根目錄本身(只列舉並刪除根的直接子項)。
public final class CleanupExecutor: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (CleanupRunProgress) async -> Void

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func run(
        categories: [CleanupCategory],
        progress: ProgressHandler? = nil
    ) async -> CleanupRunResult {
        var categoryResults: [CleanupCategoryRunResult] = []
        var skipped: [DiskSpaceSkippedPath] = []

        for category in categories {
            if Task.isCancelled { break }
            var reclaimed: UInt64 = 0
            var deleted = 0

            for root in category.roots {
                guard let children = try? fileManager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                ) else { continue }

                for child in children {
                    if Task.isCancelled { break }

                    if CleanupSizing.isSymbolicLink(child, fileManager: fileManager) {
                        skipped.append(DiskSpaceSkippedPath(url: child, reason: "Symbolic link skipped"))
                        continue
                    }
                    guard CleanupSafety.isDeletable(child, within: category.roots, fileManager: fileManager) else {
                        skipped.append(DiskSpaceSkippedPath(url: child, reason: "Blocked by safety guard"))
                        continue
                    }

                    let size = CleanupSizing.size(of: child, fileManager: fileManager)
                    do {
                        try fileManager.removeItem(at: child)
                        reclaimed += size
                        deleted += 1
                        if let progress {
                            await progress(CleanupRunProgress(
                                categoryID: category.id, currentPath: child.path, deletedCount: deleted
                            ))
                        }
                    } catch {
                        skipped.append(DiskSpaceSkippedPath(
                            url: child, reason: "Delete failed: \(error.localizedDescription)"
                        ))
                    }
                }
            }

            categoryResults.append(CleanupCategoryRunResult(
                id: category.id, reclaimedBytes: reclaimed, deletedCount: deleted
            ))
        }

        return CleanupRunResult(categories: categoryResults, skippedPaths: skipped)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CleanupExecutorTests`
Expected: PASS(3 個案例)。

- [ ] **Step 5: 跑整包測試確認無回歸**

Run: `swift test`
Expected: 全綠(含既有測試 + 新增四組 Cleanup 測試)。

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/Cleanup/CleanupExecutor.swift Tests/GlanceCoreTests/CleanupExecutorTests.swift
git commit -m "feat: [core] 新增清理執行器 CleanupExecutor 並驗證護欄"
```

---

## Task 6: ViewModel 五狀態機 `CleanupViewModel`

**Files:**
- Create: `GlanceApp/Cleanup/CleanupViewModel.swift`

> UI glue,比照既有 `DiskSpaceAnalyzerViewModel`(同樣無獨立單元測試);驗證留待 Task 9 實機。

- [ ] **Step 1: 建立 `CleanupViewModel.swift`**

```swift
import Combine
import Foundation
import GlanceCore

@MainActor
final class CleanupViewModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case selecting
        case confirming
        case running
        case done
    }

    struct Row: Identifiable {
        let category: CleanupCategory
        let result: CleanupCategoryResult
        var isSelected: Bool
        var id: CleanupCategoryID { category.id }
    }

    @Published private(set) var phase: Phase = .scanning
    @Published private(set) var rows: [Row] = []
    @Published private(set) var currentPath: String?
    @Published private(set) var runResult: CleanupRunResult?

    private let categories: [CleanupCategory]
    private let scanner: CleanupScanner
    private let executor: CleanupExecutor
    private var scanTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(
        categories: [CleanupCategory] = CleanupCategory.defaults(),
        scanner: CleanupScanner = CleanupScanner(),
        executor: CleanupExecutor = CleanupExecutor()
    ) {
        self.categories = categories
        self.scanner = scanner
        self.executor = executor
    }

    deinit {
        scanTask?.cancel()
        runTask?.cancel()
    }

    // MARK: Derived

    var selectedRows: [Row] { rows.filter(\.isSelected) }
    var selectedCategories: [CleanupCategory] { selectedRows.map(\.category) }
    var selectedCount: Int { selectedRows.count }
    var selectedBytes: UInt64 { selectedRows.reduce(0) { $0 + $1.result.reclaimableBytes } }
    var hasSelection: Bool { !selectedRows.isEmpty }

    // MARK: Actions

    func startScan() {
        scanTask?.cancel()
        phase = .scanning
        rows = []
        currentPath = nil
        let categories = categories
        scanTask = Task { [weak self, scanner] in
            let results = await scanner.scan(categories: categories) { [weak self] progress in
                await self?.applyScanProgress(progress)
            }
            await self?.applyScanResults(results)
        }
    }

    func toggle(_ id: CleanupCategoryID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isSelected.toggle()
    }

    func requestConfirmation() {
        guard hasSelection else { return }
        phase = .confirming
    }

    func cancelConfirmation() {
        phase = .selecting
    }

    func confirmDelete() {
        runTask?.cancel()
        phase = .running
        currentPath = nil
        let targets = selectedCategories
        runTask = Task { [weak self, executor] in
            let result = await executor.run(categories: targets) { [weak self] progress in
                await self?.applyRunProgress(progress)
            }
            await self?.applyRunResult(result)
        }
    }

    // MARK: Apply (MainActor)

    private func applyScanProgress(_ progress: CleanupScanProgress) {
        guard phase == .scanning else { return }
        currentPath = progress.currentPath
    }

    private func applyScanResults(_ results: [CleanupCategoryResult]) {
        rows = categories.compactMap { category in
            guard let result = results.first(where: { $0.id == category.id }) else { return nil }
            // 預設勾選有可回收項目的類別。
            return Row(category: category, result: result, isSelected: result.itemCount > 0)
        }
        currentPath = nil
        phase = .selecting
        scanTask = nil
    }

    private func applyRunProgress(_ progress: CleanupRunProgress) {
        guard phase == .running else { return }
        currentPath = progress.currentPath
    }

    private func applyRunResult(_ result: CleanupRunResult) {
        runResult = result
        currentPath = nil
        phase = .done
        runTask = nil
    }
}
```

- [ ] **Step 2: 編譯 app target 確認通過**

Run: `swift build --target GlanceApp`
Expected: 編譯成功(`CleanupView` 尚未被引用,VM 可獨立編譯)。

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/Cleanup/CleanupViewModel.swift
git commit -m "feat: [app] 新增清理視窗 ViewModel 五狀態機"
```

---

## Task 7: 視窗 `CleanupView`

**Files:**
- Create: `GlanceApp/Cleanup/CleanupView.swift`

- [ ] **Step 1: 建立 `CleanupView.swift`**

```swift
import AppKit
import SwiftUI
import GlanceCore

struct CleanupView: View {
    @StateObject private var viewModel = CleanupViewModel()

    private let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 440)
        .sheet(isPresented: confirmBinding) { confirmationSheet }
        .onAppear {
            if viewModel.phase == .scanning, viewModel.rows.isEmpty {
                viewModel.startScan()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("清理")
                .font(.system(size: 20, weight: .semibold))
            Text("掃描可回收空間,勾選後永久刪除。快取會在 App 下次使用時自動重建。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .scanning:
            scanningView
        case .selecting, .confirming:
            selectionView
        case .running:
            runningView
        case .done:
            doneView
        }
    }

    // MARK: Scanning

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("掃描中…")
                .font(.system(size: 13))
            Text(viewModel.currentPath ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Selection

    private var selectionView: some View {
        VStack(spacing: 12) {
            List(viewModel.rows) { row in
                Button {
                    viewModel.toggle(row.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(row.isSelected ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.category.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(pathSummary(row.category))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 12)

                        Text(Formatters.bytes(row.result.reclaimableBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("已選 \(viewModel.selectedCount) 類 · \(Formatters.bytes(viewModel.selectedBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.requestConfirmation()
                } label: {
                    Text("清理選取…")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasSelection)
            }
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
            Label("永久刪除", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)

            Text("將永久刪除約 \(Formatters.bytes(viewModel.selectedBytes)),無法復原。快取會在 App 下次使用時自動重建。")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.selectedRows) { row in
                    HStack {
                        Text(row.category.displayName)
                        Spacer()
                        Text(Formatters.bytes(row.result.reclaimableBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }

            HStack {
                Spacer()
                Button("取消") { viewModel.cancelConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Button("永久刪除") { viewModel.confirmDelete() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: Running

    private var runningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("清理中…")
                .font(.system(size: 13))
            Text(viewModel.currentPath ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.18), lineWidth: 10)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text(Formatters.bytes(viewModel.runResult?.totalReclaimedBytes ?? 0))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已回收")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("刪除 \(viewModel.runResult?.totalDeletedCount ?? 0) 項 · 跳過 \(viewModel.runResult?.skippedCount ?? 0) 項(無權限)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("完成") { dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func pathSummary(_ category: CleanupCategory) -> String {
        category.roots
            .map { $0.path.replacingOccurrences(of: homePath, with: "~") }
            .joined(separator: "、")
    }

    private func dismissWindow() {
        NSApplication.shared.keyWindow?.close()
    }
}
```

- [ ] **Step 2: 編譯 app target 確認通過**

Run: `swift build --target GlanceApp`
Expected: 編譯成功(`CleanupView` 尚未在 Scene 註冊,但可獨立編譯)。

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/Cleanup/CleanupView.swift
git commit -m "feat: [app] 新增清理視窗 CleanupView 五狀態 UI"
```

---

## Task 8: 開窗註冊與下拉 footer 按鈕

**Files:**
- Modify: `GlanceApp/GlanceApp.swift:16-18`(在 disk-space-analyzer Window 後新增)
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1: 在 `GlanceApp.swift` 註冊清理視窗**

把現有 Scene 中的 disk 視窗區塊:

```swift
        Window("Disk Space Analyzer", id: "disk-space-analyzer") {
            DiskSpaceAnalyzerWindow()
        }
```

改為其後緊接清理視窗:

```swift
        Window("Disk Space Analyzer", id: "disk-space-analyzer") {
            DiskSpaceAnalyzerWindow()
        }

        Window("清理", id: "cleanup") {
            CleanupView()
        }
```

- [ ] **Step 2: 在 `DropdownView.swift` 加入 openWindow 環境值**

把:

```swift
    @ObservedObject var store: MetricsStore
    @Environment(\.openSettings) private var openSettings
```

改為:

```swift
    @ObservedObject var store: MetricsStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
```

- [ ] **Step 3: 在 footer 新增「清理…」按鈕**

把 `footer` 中「設定」按鈕區塊(`Button { openSettingsWindow() } ... .foregroundStyle(.secondary)`)之後、`Spacer()` 之前,插入清理按鈕。即把:

```swift
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
```

改為:

```swift
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                openCleanupWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                    Text("清理")
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

            Spacer()
```

- [ ] **Step 4: 在 `DropdownView.swift` 新增開窗方法**

在既有 `openSettingsWindow()` 方法之後新增(比照 `DiskSection.openAnalyzerWindow()`):

```swift
    private func openCleanupWindow() {
        openWindow(id: "cleanup")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
```

- [ ] **Step 5: 編譯確認通過**

Run: `swift build`
Expected: 整個 package 編譯成功。

- [ ] **Step 6: Commit**

```bash
git add GlanceApp/GlanceApp.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 下拉 footer 新增清理入口並註冊清理視窗"
```

---

## Task 9: 整包驗證與實機驗收

**Files:** 無(僅 build + 啟動驗證)

> 依記憶 [[verify-by-launching-app]]:test/build 全綠仍可能啟動才出問題,務必實際組 `.app` 啟動。

- [ ] **Step 1: 全測試 + release build**

Run: `swift test && swift build -c release`
Expected: 測試全綠;release 編譯成功。

- [ ] **Step 2: 組出 `.app` 並啟動**

依專案既有打包方式組出 `Glance.app`(參考記憶 [[glance-brew-packaging]]:純 `swift build` + 手動組 bundle,勿用 xcodebuild)。啟動後:
- 點開選單列下拉,確認 footer 出現「清理」按鈕。
- 點「清理」開窗,確認進入掃描中 → 勾選畫面,各類別大小看起來合理(尤其垃圾桶與 `~/Library/Caches`)。

Expected: app 不崩;掃描完成顯示三類別與可回收大小;受 TCC 保護的子路徑落入掃描略過、不崩。

- [ ] **Step 3: 對垃圾桶實清一次驗收**

先在 Finder 丟幾個檔到垃圾桶 → 回 app 重新掃描 → 只勾「垃圾桶」→「清理選取…」→ 確認 sheet 顯示紅字警告與大小 →「永久刪除」。
Expected:
- 執行中顯示進度 + 目前刪除路徑。
- 完成顯示圓環回收量 + 「刪除 N 項 · 跳過 M 項(無權限)」。
- Finder 垃圾桶已清空、`~/.Trash` 目錄本身仍在;app 不崩。

- [ ] **Step 4: 更新路線圖記憶**

更新記憶檔 `mole-inspired-roadmap.md`:標記階段二(清理)已完成,僅剩階段三(解除安裝)。

- [ ] **Step 5: Commit(若有打包腳本/文件改動)**

```bash
git add -A
git commit -m "chore: [app] 清理功能階段二實機驗收完成"
```

---

## Self-Review

**Spec coverage:**
- 三類別與確切路徑 → Task 1 `defaults(home:)`(trash/userCaches/devCaches 路徑逐一比對測試)。✓
- 安全護欄(只刪根底下、正規化前綴、非根本身、擋 `../`、跳 symlink) → Task 2 `CleanupSafety` + 6 測試;Task 5 executor 二度套用。✓
- async 掃描 + 進度 + 可回收 bytes/項目數 + 跳 symlink → Task 4 `CleanupScanner`。✓
- 刪內容物保留根、回收量、失敗進 skipped 不中斷、惡意項被擋 → Task 5 `CleanupExecutor` + 3 測試。✓
- 沿用 `DiskSpaceSkippedPath` → `CleanupRunResult.skippedPaths` 採用既有型別。✓
- UI 五狀態(掃描→勾選→確認 sheet→執行→完成)+ 下拉 footer 開窗 → Task 6/7/8。✓
- 確認 sheet 紅字警告 + 類別與大小 + 取消/永久刪除 → Task 7 `confirmationSheet`。✓
- 完成圓環 + 「刪除 N 項 · 跳過 M 項」 → Task 7 `doneView`。✓
- 實機驗收(掃描合理、垃圾桶實清、不崩) → Task 9。✓

**Placeholder scan:** 無 TBD/「適當處理」等佔位;每個 code step 皆含完整可編譯程式碼。✓

**Type consistency:** `CleanupCategoryID`、`CleanupCategory`、`CleanupCategoryResult`、`CleanupCategoryRunResult`、`CleanupRunResult`(`categories`/`skippedPaths`/`totalReclaimedBytes`/`totalDeletedCount`/`skippedCount`)、`CleanupScanProgress`、`CleanupRunProgress`、`CleanupSafety.isDeletable(_:within:fileManager:)`、`CleanupSizing.size(of:fileManager:)`/`isSymbolicLink(_:fileManager:)`、`CleanupScanner.scan(categories:progress:)`、`CleanupExecutor.run(categories:progress:)` 跨任務命名一致。✓
