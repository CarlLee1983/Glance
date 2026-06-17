# 分析空間改善 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把唯讀的磁碟空間排行榜改寫成「樹狀下鑽 + 佔比長條 + 移到垃圾桶」的互動式分析器,並加入掃描快取與 Bento UI。

**Architecture:** 核心邏輯全部放在 `GlanceCore`(可被 `GlanceCoreTests` 測試):`DiskNode` 樹模型、`DiskSpaceAnalyzer` 並行建樹引擎、`DiskScanCache` 快取、`DiskTrashSafety`/`DiskTrashService` 刪除護欄與執行、`DiskTreeNavigator` 純導覽邏輯。App 端 `DiskAnalyzer/` 改寫 ViewModel/Window 並拆出 4 個 Bento 風格元件,以 build + 啟動驗證(無 App 測試 target)。

**Tech Stack:** Swift 6 concurrency(`async/await`、`TaskGroup`、actor)、`FileManager`、`Codable`(JSON 快取)、SwiftUI、XCTest。

**驗證指令:**
- 核心測試:`swift test --filter GlanceCoreTests`
- 建置:`swift build`
- App 啟動驗證:依專案慣例(`glance` 啟動器或 `xcodebuild`/手動組 .app),掃描家目錄、下鑽、勾選、移到垃圾桶。

---

## 檔案結構

**新增(GlanceCore):**
- `Sources/GlanceCore/Model/DiskNode.swift` — 樹節點 + 樹掃描進度/結果型別
- `Sources/GlanceCore/Store/DiskScanCache.swift` — Codable 樹快取
- `Sources/GlanceCore/Uninstall/DiskTrashSafety.swift` — 任意深度刪除護欄
- `Sources/GlanceCore/Uninstall/DiskTrashService.swift` — 刪除執行器
- `Sources/GlanceCore/Sampling/DiskTreeNavigator.swift` — 純導覽/移除/重算邏輯

**改寫(GlanceCore):**
- `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift` — 改為並行建樹
- `Sources/GlanceCore/Model/DiskSpaceItem.swift` — `DiskSpaceItemKind` 加 `Codable`;移除改寫後不再使用的平面型別

**新增(GlanceApp):**
- `GlanceApp/DiskAnalyzer/Components/BreadcrumbBar.swift`
- `GlanceApp/DiskAnalyzer/Components/DiskNodeRow.swift`
- `GlanceApp/DiskAnalyzer/Components/ScanSummaryStrip.swift`
- `GlanceApp/DiskAnalyzer/Components/TrashActionBar.swift`

**改寫(GlanceApp):**
- `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift`
- `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift`
- `GlanceApp/GlanceApp.swift:16` — 視窗標題改「磁碟空間分析」

**測試:**
- `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift` — 改寫為樹斷言
- `Tests/GlanceCoreTests/DiskScanCacheTests.swift`(新)
- `Tests/GlanceCoreTests/DiskTrashSafetyTests.swift`(新)
- `Tests/GlanceCoreTests/DiskTrashServiceTests.swift`(新)
- `Tests/GlanceCoreTests/DiskTreeNavigatorTests.swift`(新)

---

## Task 1: DiskNode 樹模型與掃描結果型別

**Files:**
- Create: `Sources/GlanceCore/Model/DiskNode.swift`
- Modify: `Sources/GlanceCore/Model/DiskSpaceItem.swift:3-6`(`DiskSpaceItemKind` 加 `Codable`)
- Test: `Tests/GlanceCoreTests/DiskNodeTests.swift`(新)

- [ ] **Step 1: 讓 `DiskSpaceItemKind` 可序列化**

修改 `Sources/GlanceCore/Model/DiskSpaceItem.swift` 第 3 行:

```swift
public enum DiskSpaceItemKind: Equatable, Sendable, Codable {
    case file
    case folder
}
```

- [ ] **Step 2: 寫失敗測試**

建立 `Tests/GlanceCoreTests/DiskNodeTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskNodeTests: XCTestCase {
    func testDefaultNameDerivesFromURL() {
        let node = DiskNode(
            url: URL(fileURLWithPath: "/tmp/foo/bar.txt"),
            kind: .file, sizeBytes: 10, modifiedAt: nil
        )
        XCTAssertEqual(node.name, "bar.txt")
        XCTAssertEqual(node.id, "/tmp/foo/bar.txt")
        XCTAssertFalse(node.isAggregate)
    }

    func testCodableRoundTripPreservesTree() throws {
        let child = DiskNode(url: URL(fileURLWithPath: "/r/a"), kind: .file, sizeBytes: 5, modifiedAt: nil)
        let root = DiskNode(
            url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 5,
            modifiedAt: Date(timeIntervalSince1970: 1000), children: [child]
        )
        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(DiskNode.self, from: data)
        XCTAssertEqual(decoded, root)
    }
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `swift test --filter DiskNodeTests`
Expected: FAIL — `cannot find 'DiskNode' in scope`

- [ ] **Step 4: 建立 DiskNode 與結果型別**

建立 `Sources/GlanceCore/Model/DiskNode.swift`:

```swift
import Foundation

/// 磁碟掃描的樹節點。value type、遞迴結構,天然 Sendable + Codable(供快取)。
/// `isAggregate == true` 表示「其他 N 個項目」合成節點:只記總和與計數,不可下鑽、不可選取。
public struct DiskNode: Identifiable, Equatable, Sendable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: DiskSpaceItemKind
    public let sizeBytes: UInt64
    public let modifiedAt: Date?
    public let children: [DiskNode]
    public let isAggregate: Bool
    public let aggregateCount: Int

    public init(
        url: URL,
        name: String? = nil,
        kind: DiskSpaceItemKind,
        sizeBytes: UInt64,
        modifiedAt: Date?,
        children: [DiskNode] = [],
        isAggregate: Bool = false,
        aggregateCount: Int = 0
    ) {
        self.url = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.children = children
        self.isAggregate = isAggregate
        self.aggregateCount = aggregateCount
    }

    /// 可下鑽:資料夾且非合成節點。
    public var isDrillable: Bool { kind == .folder && !isAggregate && !children.isEmpty }
}

public struct DiskTreeScanProgress: Equatable, Sendable {
    public let scannedCount: Int
    public let skippedCount: Int
    public let currentPath: String?

    public init(scannedCount: Int, skippedCount: Int, currentPath: String?) {
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.currentPath = currentPath
    }
}

public struct DiskTreeScanResult: Equatable, Sendable {
    public let rootURL: URL
    public let state: DiskSpaceScanState
    public let scannedCount: Int
    public let root: DiskNode?          // root 不可讀時為 nil
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(
        rootURL: URL,
        state: DiskSpaceScanState,
        scannedCount: Int,
        root: DiskNode?,
        skippedPaths: [DiskSpaceSkippedPath]
    ) {
        self.rootURL = rootURL
        self.state = state
        self.scannedCount = scannedCount
        self.root = root
        self.skippedPaths = skippedPaths
    }
}
```

- [ ] **Step 5: 跑測試確認通過**

Run: `swift test --filter DiskNodeTests`
Expected: PASS(2 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/Model/DiskNode.swift Sources/GlanceCore/Model/DiskSpaceItem.swift Tests/GlanceCoreTests/DiskNodeTests.swift
git commit -m "feat: [core] 新增 DiskNode 樹模型與樹掃描結果型別"
```

---

## Task 2: DiskSpaceAnalyzer 改為並行建樹

**Files:**
- Modify: `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift`(整檔改寫)
- Test: `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`(整檔改寫)

說明:`scan()`(回傳平面 largestFolders/Files)改為 `scanTree()`(回傳 `DiskTreeScanResult` 樹)。頂層子目錄用 `TaskGroup` 並行、子樹遞迴序列建構;`ScanReporter` actor 彙整跨並行任務的計數與 skipped 並節流回呼進度;每個資料夾以 `keepTopPerFolder` 做長尾聚合。

- [ ] **Step 1: 改寫測試檔(樹斷言 + 聚合)**

整檔覆寫 `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskSpaceAnalyzerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRanksChildrenBySizeDescending() async throws {
        let root = try makeTemporaryRoot()
        try writeFile(root.appendingPathComponent("small.bin"), byteCount: 10)
        try writeFile(root.appendingPathComponent("large.bin"), byteCount: 40)
        try writeFile(root.appendingPathComponent("medium.bin"), byteCount: 20)

        let result = await DiskSpaceAnalyzer().scanTree(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        let rootNode = try XCTUnwrap(result.root)
        XCTAssertEqual(rootNode.children.map(\.name), ["large.bin", "medium.bin", "small.bin"])
        XCTAssertEqual(rootNode.children.map(\.sizeBytes), [40, 20, 10])
        XCTAssertEqual(rootNode.sizeBytes, 70)
    }

    func testFolderSizesIncludeNestedChildren() async throws {
        let root = try makeTemporaryRoot()
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try writeFile(parent.appendingPathComponent("one.dat"), byteCount: 15)
        try writeFile(child.appendingPathComponent("two.dat"), byteCount: 25)

        let rootNode = try XCTUnwrap(await DiskSpaceAnalyzer().scanTree(rootURL: root).root)
        let parentNode = try XCTUnwrap(child(named: "parent", in: rootNode))
        let childNode = try XCTUnwrap(child(named: "child", in: parentNode))
        XCTAssertEqual(parentNode.sizeBytes, 40)
        XCTAssertEqual(childNode.sizeBytes, 25)
    }

    func testIncludesHiddenDirectories() async throws {
        let root = try makeTemporaryRoot()
        let hidden = root.appendingPathComponent(".cache", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(hidden.appendingPathComponent("cache.dat"), byteCount: 33)

        let rootNode = try XCTUnwrap(await DiskSpaceAnalyzer().scanTree(rootURL: root).root)
        let hiddenNode = try XCTUnwrap(child(named: ".cache", in: rootNode))
        XCTAssertEqual(hiddenNode.sizeBytes, 33)
    }

    func testDoesNotFollowSymlinks() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        try writeFile(outside.appendingPathComponent("outside.dat"), byteCount: 99)
        let symlink = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let rootNode = try XCTUnwrap(await DiskSpaceAnalyzer().scanTree(rootURL: root).root)
        XCTAssertNil(child(named: "outside-link", in: rootNode))
    }

    func testMissingRootIsSkippedWithoutFailingScan() async throws {
        let root = try makeTemporaryRoot()
        try FileManager.default.removeItem(at: root)

        let result = await DiskSpaceAnalyzer().scanTree(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertNil(result.root)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, root)
    }

    func testAggregatesSmallChildrenBeyondKeepTop() async throws {
        let root = try makeTemporaryRoot()
        // 5 個個別檔(大小遞減)+ keepTop=3 → 保留 3,其餘 2 收合
        try writeFile(root.appendingPathComponent("a.dat"), byteCount: 50)
        try writeFile(root.appendingPathComponent("b.dat"), byteCount: 40)
        try writeFile(root.appendingPathComponent("c.dat"), byteCount: 30)
        try writeFile(root.appendingPathComponent("d.dat"), byteCount: 20)
        try writeFile(root.appendingPathComponent("e.dat"), byteCount: 10)

        let rootNode = try XCTUnwrap(await DiskSpaceAnalyzer(keepTopPerFolder: 3).scanTree(rootURL: root).root)

        XCTAssertEqual(rootNode.children.count, 4) // 3 個別 + 1 聚合
        let aggregate = try XCTUnwrap(rootNode.children.last)
        XCTAssertTrue(aggregate.isAggregate)
        XCTAssertEqual(aggregate.aggregateCount, 2)
        XCTAssertEqual(aggregate.sizeBytes, 30) // 20 + 10
        XCTAssertEqual(rootNode.sizeBytes, 150)
    }

    func testCancellationReturnsCancelledState() async throws {
        let root = try makeTemporaryRoot()
        for index in 0..<400 {
            try writeFile(root.appendingPathComponent("file-\(index).dat"), byteCount: 1)
        }

        let analyzer = DiskSpaceAnalyzer()
        let cancellationGate = CancellationGate()
        let scanTask = Task {
            await analyzer.scanTree(rootURL: root) { progress in
                if progress.scannedCount > 0 { await cancellationGate.pauseUntilReleased() }
            }
        }

        await cancellationGate.waitForPause()
        scanTask.cancel()
        await cancellationGate.release()
        let result = await scanTask.value

        XCTAssertEqual(result.state, .cancelled)
    }

    // MARK: - Helpers

    private func child(named name: String, in node: DiskNode) -> DiskNode? {
        node.children.first { $0.name == name }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskSpaceAnalyzerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        let data = Data(repeating: 0x7A, count: byteCount)
        try data.write(to: url)
    }
}

private actor CancellationGate {
    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForPause() async {
        if isPaused { return }
        await withCheckedContinuation { continuation in pauseContinuation = continuation }
    }

    func pauseUntilReleased() async {
        guard !isPaused else { return }
        isPaused = true
        pauseContinuation?.resume()
        pauseContinuation = nil
        await withCheckedContinuation { continuation in releaseContinuation = continuation }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskSpaceAnalyzerTests`
Expected: FAIL — `value of type 'DiskSpaceAnalyzer' has no member 'scanTree'`

- [ ] **Step 3: 改寫引擎**

整檔覆寫 `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift`:

```swift
import Foundation

/// 並行建樹磁碟掃描器:頂層子目錄用 TaskGroup 並行、子樹遞迴序列建構,
/// 由下往上彙總每層大小,並對每個資料夾做長尾聚合。
/// 安全性不變式:無可變儲存屬性(只有 let),狀態彙整集中於 ScanReporter actor。
public final class DiskSpaceAnalyzer: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (DiskTreeScanProgress) async -> Void

    private let keepTopPerFolder: Int
    private let fileManager: FileManager

    public init(keepTopPerFolder: Int = 100, fileManager: FileManager = .default) {
        self.keepTopPerFolder = max(1, keepTopPerFolder)
        self.fileManager = fileManager
    }

    public func scanTree(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: ProgressHandler? = nil
    ) async -> DiskTreeScanResult {
        let reporter = ScanReporter(progress: progress)
        let builder = TreeBuilder(fileManager: fileManager, keepTopPerFolder: keepTopPerFolder, reporter: reporter)
        let root = await builder.build(url: rootURL, parallelChildren: true)
        let snapshot = await reporter.snapshot()
        return DiskTreeScanResult(
            rootURL: rootURL,
            state: Task.isCancelled ? .cancelled : .completed,
            scannedCount: snapshot.scanned,
            root: root,
            skippedPaths: snapshot.skipped
        )
    }
}

private final class TreeBuilder: @unchecked Sendable {
    let fileManager: FileManager
    let keepTopPerFolder: Int
    let reporter: ScanReporter

    init(fileManager: FileManager, keepTopPerFolder: Int, reporter: ScanReporter) {
        self.fileManager = fileManager
        self.keepTopPerFolder = keepTopPerFolder
        self.reporter = reporter
    }

    /// `parallelChildren` 只在 root 為 true:把頂層子項分散到 TaskGroup;子樹序列遞迴以限制並行爆量。
    func build(url: URL, parallelChildren: Bool) async -> DiskNode? {
        if Task.isCancelled { return nil }

        if isSymbolicLink(url) {
            await reporter.didSkip(url, reason: "Symbolic link skipped")
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            await reporter.didSkip(url, reason: "Path does not exist")
            return nil
        }

        if isDirectory.boolValue {
            return await buildDirectory(url, parallelChildren: parallelChildren)
        }
        return await buildFile(url)
    }

    private func buildFile(_ url: URL) async -> DiskNode? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            await reporter.didSkip(url, reason: "File metadata is not readable")
            return nil
        }
        if values.isSymbolicLink == true {
            await reporter.didSkip(url, reason: "Symbolic link skipped")
            return nil
        }
        guard values.isRegularFile == true else {
            await reporter.didSkip(url, reason: "Unsupported file type")
            return nil
        }
        await reporter.didScan(url.path)
        return DiskNode(
            url: url, kind: .file, sizeBytes: UInt64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }

    private func buildDirectory(_ url: URL, parallelChildren: Bool) async -> DiskNode? {
        let directoryValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(resourceKeys), options: []
        ) else {
            await reporter.didSkip(url, reason: "Directory is not readable")
            return nil
        }

        await reporter.didScan(url.path)

        var childNodes: [DiskNode] = []
        if parallelChildren {
            childNodes = await withTaskGroup(of: DiskNode?.self) { group in
                for entry in entries {
                    let childURL = url.appendingPathComponent(entry.lastPathComponent)
                    group.addTask { await self.build(url: childURL, parallelChildren: false) }
                }
                var collected: [DiskNode] = []
                for await node in group { if let node { collected.append(node) } }
                return collected
            }
        } else {
            for entry in entries {
                if Task.isCancelled { break }
                let childURL = url.appendingPathComponent(entry.lastPathComponent)
                if let node = await build(url: childURL, parallelChildren: false) {
                    childNodes.append(node)
                }
            }
        }

        let total = childNodes.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let aggregated = Aggregator.aggregate(childNodes, parentURL: url, keepTop: keepTopPerFolder)
        return DiskNode(
            url: url, kind: .folder, sizeBytes: total,
            modifiedAt: directoryValues?.contentModificationDate, children: aggregated
        )
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private var resourceKeys: Set<URLResourceKey> {
        [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
    }
}

/// 每層 children:依大小遞減排序;超過 keepTop 的長尾收合成單一聚合節點。
enum Aggregator {
    static func aggregate(_ nodes: [DiskNode], parentURL: URL, keepTop: Int) -> [DiskNode] {
        let sorted = nodes.sorted { lhs, rhs in
            lhs.sizeBytes == rhs.sizeBytes ? lhs.url.path < rhs.url.path : lhs.sizeBytes > rhs.sizeBytes
        }
        guard sorted.count > keepTop else { return sorted }

        let kept = Array(sorted.prefix(keepTop))
        let tail = Array(sorted.suffix(from: keepTop))
        let tailSize = tail.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let aggregate = DiskNode(
            url: parentURL.appendingPathComponent("·other·"),
            name: "其他 \(tail.count) 個項目",
            kind: .file,                 // 不可下鑽
            sizeBytes: tailSize,
            modifiedAt: nil,
            isAggregate: true,
            aggregateCount: tail.count
        )
        return kept + [aggregate]
    }
}

/// 跨並行任務彙整 scanned/skipped,並以「每 100 項」節流回呼進度。
private actor ScanReporter {
    struct Snapshot { let scanned: Int; let skipped: [DiskSpaceSkippedPath] }

    private let progress: DiskSpaceAnalyzer.ProgressHandler?
    private var scanned = 0
    private var skipped: [DiskSpaceSkippedPath] = []
    private var lastEmittedScanned = 0

    init(progress: DiskSpaceAnalyzer.ProgressHandler?) {
        self.progress = progress
    }

    func didScan(_ path: String) async {
        scanned += 1
        await maybeEmit(currentPath: path)
    }

    func didSkip(_ url: URL, reason: String) async {
        skipped.append(DiskSpaceSkippedPath(url: url, reason: reason))
        await maybeEmit(currentPath: url.path)
    }

    func snapshot() -> Snapshot { Snapshot(scanned: scanned, skipped: skipped) }

    private func maybeEmit(currentPath: String) async {
        guard let progress, scanned - lastEmittedScanned >= 100 else { return }
        lastEmittedScanned = scanned
        await progress(DiskTreeScanProgress(
            scannedCount: scanned, skippedCount: skipped.count, currentPath: currentPath
        ))
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskSpaceAnalyzerTests`
Expected: PASS(7 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift
git commit -m "feat: [core] DiskSpaceAnalyzer 改為並行建樹 + 長尾聚合"
```

---

## Task 3: DiskScanCache 樹快取

**Files:**
- Create: `Sources/GlanceCore/Store/DiskScanCache.swift`
- Test: `Tests/GlanceCoreTests/DiskScanCacheTests.swift`(新)

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/DiskScanCacheTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskScanCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskScanCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleRoot() -> DiskNode {
        let child = DiskNode(url: URL(fileURLWithPath: "/r/a.dat"), kind: .file, sizeBytes: 5, modifiedAt: nil)
        return DiskNode(url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 5, modifiedAt: nil, children: [child])
    }

    func testSaveThenLoadRoundTrips() throws {
        let cache = DiskScanCache(directory: directory)
        let root = sampleRoot()
        let rootURL = URL(fileURLWithPath: "/r")
        let when = Date(timeIntervalSince1970: 1700)

        try cache.save(root: root, rootURL: rootURL, scannedAt: when)
        let loaded = try XCTUnwrap(cache.load(rootURL: rootURL))

        XCTAssertEqual(loaded.root, root)
        XCTAssertEqual(loaded.scannedAt, when)
    }

    func testLoadMissingReturnsNil() {
        let cache = DiskScanCache(directory: directory)
        XCTAssertNil(cache.load(rootURL: URL(fileURLWithPath: "/does/not/exist")))
    }

    func testClearRemovesEntry() throws {
        let cache = DiskScanCache(directory: directory)
        let rootURL = URL(fileURLWithPath: "/r")
        try cache.save(root: sampleRoot(), rootURL: rootURL, scannedAt: Date(timeIntervalSince1970: 1))
        cache.clear(rootURL: rootURL)
        XCTAssertNil(cache.load(rootURL: rootURL))
    }

    func testDistinctRootsDoNotCollide() throws {
        let cache = DiskScanCache(directory: directory)
        let a = URL(fileURLWithPath: "/alpha")
        let b = URL(fileURLWithPath: "/beta")
        try cache.save(root: DiskNode(url: a, kind: .folder, sizeBytes: 1, modifiedAt: nil), rootURL: a, scannedAt: Date(timeIntervalSince1970: 1))
        try cache.save(root: DiskNode(url: b, kind: .folder, sizeBytes: 2, modifiedAt: nil), rootURL: b, scannedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(cache.load(rootURL: a)?.root.sizeBytes, 1)
        XCTAssertEqual(cache.load(rootURL: b)?.root.sizeBytes, 2)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskScanCacheTests`
Expected: FAIL — `cannot find 'DiskScanCache' in scope`

- [ ] **Step 3: 實作快取**

建立 `Sources/GlanceCore/Store/DiskScanCache.swift`:

```swift
import Foundation

public struct DiskScanCacheEntry: Codable, Equatable, Sendable {
    public let rootPath: String
    public let scannedAt: Date
    public let root: DiskNode

    public init(rootPath: String, scannedAt: Date, root: DiskNode) {
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.root = root
    }
}

/// 把整棵 DiskNode 以 JSON 序列化到 Application Support,key = 正規化後 root 路徑的穩定雜湊。
public final class DiskScanCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    public func save(root: DiskNode, rootURL: URL, scannedAt: Date) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = DiskScanCacheEntry(
            rootPath: rootURL.standardizedFileURL.path, scannedAt: scannedAt, root: root
        )
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: rootURL), options: .atomic)
    }

    public func load(rootURL: URL) -> DiskScanCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: rootURL)) else { return nil }
        return try? JSONDecoder().decode(DiskScanCacheEntry.self, from: data)
    }

    public func clear(rootURL: URL) {
        try? fileManager.removeItem(at: fileURL(for: rootURL))
    }

    private func fileURL(for rootURL: URL) -> URL {
        let key = rootURL.standardizedFileURL.path
        return directory.appendingPathComponent("scan-\(Self.stableHash(key)).json")
    }

    /// djb2:Hasher 每次執行 seed 不同,不可用於檔名;此函式跨執行穩定。
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Glance/DiskScanCache", isDirectory: true)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskScanCacheTests`
Expected: PASS(4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Store/DiskScanCache.swift Tests/GlanceCoreTests/DiskScanCacheTests.swift
git commit -m "feat: [core] 新增 DiskScanCache 樹快取"
```

---

## Task 4: DiskTrashSafety 任意深度刪除護欄

**Files:**
- Create: `Sources/GlanceCore/Uninstall/DiskTrashSafety.swift`
- Test: `Tests/GlanceCoreTests/DiskTrashSafetyTests.swift`(新)

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/DiskTrashSafetyTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskTrashSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskTrashSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("deep/nested", isDirectory: true), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAcceptsDeepDescendant() {
        let target = root.appendingPathComponent("deep/nested")
        XCTAssertTrue(DiskTrashSafety.isDeletable(target, withinRoot: root, protectedPaths: []))
    }

    func testRejectsRootItself() {
        XCTAssertFalse(DiskTrashSafety.isDeletable(root, withinRoot: root, protectedPaths: []))
    }

    func testRejectsPathOutsideRoot() {
        let outside = root.deletingLastPathComponent().appendingPathComponent("sibling")
        XCTAssertFalse(DiskTrashSafety.isDeletable(outside, withinRoot: root, protectedPaths: []))
    }

    func testRejectsSymlinkLeaf() throws {
        let realDir = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDir)
        XCTAssertFalse(DiskTrashSafety.isDeletable(link, withinRoot: root, protectedPaths: []))
    }

    func testRejectsProtectedPath() {
        let protectedDir = root.appendingPathComponent("deep")
        XCTAssertFalse(DiskTrashSafety.isDeletable(protectedDir, withinRoot: root, protectedPaths: [protectedDir]))
        // 但其子項仍可刪
        XCTAssertTrue(DiskTrashSafety.isDeletable(protectedDir.appendingPathComponent("nested"), withinRoot: root, protectedPaths: [protectedDir]))
    }

    func testRejectsShallowRoot() {
        XCTAssertFalse(DiskTrashSafety.isDeletable(URL(fileURLWithPath: "/etc"), withinRoot: URL(fileURLWithPath: "/"), protectedPaths: []))
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskTrashSafetyTests`
Expected: FAIL — `cannot find 'DiskTrashSafety' in scope`

- [ ] **Step 3: 實作護欄**

建立 `Sources/GlanceCore/Uninstall/DiskTrashSafety.swift`:

```swift
import Foundation

/// 分析器的「移到垃圾桶」護欄。異於 UninstallSafety 的 depth-1:此處允許任意深度,
/// 但目標必須是掃描 root 的「嚴格子孫」、非 root/祖先、非 symlink 葉、且不在保護清單。
public enum DiskTrashSafety {
    /// 即使位於 root 之下仍硬擋整包刪除的關鍵頂層目錄(預設清單)。
    public static func defaultProtectedPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        ["Library", ".ssh", "Documents", "Desktop", "Pictures", "Movies", "Music"]
            .map { home.appendingPathComponent($0) }
    }

    public static func isDeletable(
        _ url: URL,
        withinRoot root: URL,
        protectedPaths: [URL] = defaultProtectedPaths(),
        fileManager: FileManager = .default
    ) -> Bool {
        // 1) 拒絕 symlink 葉(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        let standardized = url.standardizedFileURL
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        // 2) root 防呆:拒絕過淺的根(如 "/")。
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard rootComponents.count > 1 else { return false }

        // 3) 必須是 root 的嚴格子孫(元件數 > root 且前綴相符)。
        let targetComponents = standardized.resolvingSymlinksInPath().pathComponents
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            return false
        }

        // 4) 拒絕保護清單(精確比對整個目錄)。
        for protected in protectedPaths {
            if targetComponents == protected.standardizedFileURL.resolvingSymlinksInPath().pathComponents {
                return false
            }
        }

        return true
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskTrashSafetyTests`
Expected: PASS(6 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/DiskTrashSafety.swift Tests/GlanceCoreTests/DiskTrashSafetyTests.swift
git commit -m "feat: [core] 新增 DiskTrashSafety 任意深度刪除護欄"
```

---

## Task 5: DiskTrashService 刪除執行器

**Files:**
- Create: `Sources/GlanceCore/Uninstall/DiskTrashService.swift`
- Test: `Tests/GlanceCoreTests/DiskTrashServiceTests.swift`(新)

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/DiskTrashServiceTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskTrashServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskTrashServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTrashesAllowedItemsAndCountsBytes() {
        let trashed = TrashRecorder()
        let service = DiskTrashService(trash: { trashed.record($0) })
        let item = DiskTrashRequestItem(url: root.appendingPathComponent("a.dat"), sizeBytes: 100)

        let result = service.run(items: [item], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 1)
        XCTAssertEqual(result.freedBytes, 100)
        XCTAssertTrue(result.skippedPaths.isEmpty)
        XCTAssertEqual(trashed.urls, [item.url])
    }

    func testSkipsBlockedItemsWithoutTrashing() {
        let trashed = TrashRecorder()
        let service = DiskTrashService(trash: { trashed.record($0) })
        // root 本身會被護欄擋下
        let item = DiskTrashRequestItem(url: root, sizeBytes: 999)

        let result = service.run(items: [item], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 0)
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertTrue(trashed.urls.isEmpty)
    }

    func testContinuesAfterTrashFailure() {
        struct TrashError: Error {}
        let service = DiskTrashService(trash: { url in
            if url.lastPathComponent == "boom.dat" { throw TrashError() }
        })
        let ok = DiskTrashRequestItem(url: root.appendingPathComponent("ok.dat"), sizeBytes: 10)
        let boom = DiskTrashRequestItem(url: root.appendingPathComponent("boom.dat"), sizeBytes: 20)

        let result = service.run(items: [boom, ok], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 1)
        XCTAssertEqual(result.freedBytes, 10)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, boom.url)
    }
}

private final class TrashRecorder: @unchecked Sendable {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskTrashServiceTests`
Expected: FAIL — `cannot find 'DiskTrashService' in scope`

- [ ] **Step 3: 實作執行器**

建立 `Sources/GlanceCore/Uninstall/DiskTrashService.swift`:

```swift
import Foundation

public struct DiskTrashRequestItem: Equatable, Sendable {
    public let url: URL
    public let sizeBytes: UInt64
    public init(url: URL, sizeBytes: UInt64) {
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

public struct DiskTrashResult: Equatable, Sendable {
    public let trashedCount: Int
    public let freedBytes: UInt64
    public let skippedPaths: [DiskSpaceSkippedPath]
    public init(trashedCount: Int, freedBytes: UInt64, skippedPaths: [DiskSpaceSkippedPath]) {
        self.trashedCount = trashedCount
        self.freedBytes = freedBytes
        self.skippedPaths = skippedPaths
    }
}

/// 逐項先過 DiskTrashSafety,再以可注入的移除動作(預設移到垃圾桶)處理;任一項失敗不中斷其餘。
public final class DiskTrashService: @unchecked Sendable {
    public typealias TrashAction = @Sendable (URL) throws -> Void

    private let fileManager: FileManager
    private let trash: TrashAction

    public init(fileManager: FileManager = .default, trash: TrashAction? = nil) {
        self.fileManager = fileManager
        self.trash = trash ?? { try fileManager.trashItem(at: $0, resultingItemURL: nil) }
    }

    public func run(
        items: [DiskTrashRequestItem],
        withinRoot root: URL,
        protectedPaths: [URL] = DiskTrashSafety.defaultProtectedPaths()
    ) -> DiskTrashResult {
        var freed: UInt64 = 0
        var trashed = 0
        var skipped: [DiskSpaceSkippedPath] = []

        for item in items {
            guard DiskTrashSafety.isDeletable(
                item.url, withinRoot: root, protectedPaths: protectedPaths, fileManager: fileManager
            ) else {
                skipped.append(DiskSpaceSkippedPath(url: item.url, reason: "Blocked by safety guard"))
                continue
            }
            do {
                try trash(item.url)
                freed += item.sizeBytes
                trashed += 1
            } catch {
                skipped.append(DiskSpaceSkippedPath(
                    url: item.url, reason: "Trash failed: \(error.localizedDescription)"
                ))
            }
        }

        return DiskTrashResult(trashedCount: trashed, freedBytes: freed, skippedPaths: skipped)
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskTrashServiceTests`
Expected: PASS(3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Uninstall/DiskTrashService.swift Tests/GlanceCoreTests/DiskTrashServiceTests.swift
git commit -m "feat: [core] 新增 DiskTrashService 刪除執行器"
```

---

## Task 6: DiskTreeNavigator 純導覽邏輯

**Files:**
- Create: `Sources/GlanceCore/Sampling/DiskTreeNavigator.swift`
- Test: `Tests/GlanceCoreTests/DiskTreeNavigatorTests.swift`(新)

說明:把下鑽/麵包屑/移除+重算抽成純 value type,讓 ViewModel 只做 SwiftUI 綁定。`path` 以節點 `id`(url.path)記錄,較名稱穩健。

- [ ] **Step 1: 寫失敗測試**

建立 `Tests/GlanceCoreTests/DiskTreeNavigatorTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskTreeNavigatorTests: XCTestCase {
    /// 樹:root(/r, 100) ├ big(/r/big, 70) │ └ leaf(/r/big/leaf.dat, 70)  └ small(/r/small.dat, 30)
    private func makeTree() -> DiskNode {
        let leaf = DiskNode(url: URL(fileURLWithPath: "/r/big/leaf.dat"), kind: .file, sizeBytes: 70, modifiedAt: nil)
        let big = DiskNode(url: URL(fileURLWithPath: "/r/big"), kind: .folder, sizeBytes: 70, modifiedAt: nil, children: [leaf])
        let small = DiskNode(url: URL(fileURLWithPath: "/r/small.dat"), kind: .file, sizeBytes: 30, modifiedAt: nil)
        return DiskNode(url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 100, modifiedAt: nil, children: [big, small])
    }

    func testDrillUpdatesCurrentNodeAndBreadcrumb() {
        var nav = DiskTreeNavigator(root: makeTree())
        let big = nav.currentNode.children.first { $0.name == "big" }!
        nav.drill(into: big)
        XCTAssertEqual(nav.currentNode.id, "/r/big")
        XCTAssertEqual(nav.breadcrumb.map(\.name), ["r", "big"])
        XCTAssertTrue(nav.canGoUp)
    }

    func testDrillIgnoresNonFolder() {
        var nav = DiskTreeNavigator(root: makeTree())
        let small = nav.currentNode.children.first { $0.name == "small.dat" }!
        nav.drill(into: small)
        XCTAssertEqual(nav.currentNode.id, "/r")
    }

    func testGoUpAndJumpToDepth() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.goUp()
        XCTAssertEqual(nav.currentNode.id, "/r")
        XCTAssertFalse(nav.canGoUp)

        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.jump(toDepth: 0)
        XCTAssertEqual(nav.currentNode.id, "/r")
    }

    func testRemoveRecomputesAncestorSizes() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.remove(ids: ["/r/small.dat"])
        XCTAssertEqual(nav.root.sizeBytes, 70)
        XCTAssertNil(nav.currentNode.children.first { $0.name == "small.dat" })
    }

    func testRemoveNodeOnPathClampsPath() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.remove(ids: ["/r/big"])
        XCTAssertEqual(nav.currentNode.id, "/r") // path 被裁回有效層
        XCTAssertEqual(nav.root.sizeBytes, 30)
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter DiskTreeNavigatorTests`
Expected: FAIL — `cannot find 'DiskTreeNavigator' in scope`

- [ ] **Step 3: 實作導覽器**

建立 `Sources/GlanceCore/Sampling/DiskTreeNavigator.swift`:

```swift
import Foundation

/// 純 value type:持有整棵樹 + 目前路徑(節點 id 序列),提供下鑽/回上層/跳層,
/// 以及移除節點後沿祖先重算大小。無副作用,可完整單元測試。
public struct DiskTreeNavigator: Equatable, Sendable {
    public private(set) var root: DiskNode
    /// 從 root 到目前節點的子節點 id 序列(不含 root)。
    public private(set) var path: [String]

    public init(root: DiskNode) {
        self.root = root
        self.path = []
    }

    public var breadcrumb: [DiskNode] {
        var nodes = [root]
        var node = root
        for id in path {
            guard let next = node.children.first(where: { $0.id == id && !$0.isAggregate }) else { break }
            nodes.append(next)
            node = next
        }
        return nodes
    }

    public var currentNode: DiskNode { breadcrumb.last ?? root }

    public var canGoUp: Bool { !path.isEmpty }

    public mutating func drill(into child: DiskNode) {
        guard child.kind == .folder, !child.isAggregate,
              currentNode.children.contains(where: { $0.id == child.id }) else { return }
        path.append(child.id)
    }

    public mutating func goUp() {
        if !path.isEmpty { path.removeLast() }
    }

    /// depth 0 = root;depth n = path 前 n 段。
    public mutating func jump(toDepth depth: Int) {
        guard depth >= 0, depth <= path.count else { return }
        path = Array(path.prefix(depth))
    }

    public mutating func remove(ids: Set<String>) {
        root = Self.removing(ids: ids, from: root)
        clampPath()
    }

    /// 移除指定 id 的節點,並由下往上重算各層 folder 大小(file 與 aggregate 保持原值)。
    private static func removing(ids: Set<String>, from node: DiskNode) -> DiskNode {
        guard !node.children.isEmpty else { return node }
        let kept = node.children
            .filter { !ids.contains($0.id) }
            .map { removing(ids: ids, from: $0) }
        guard node.kind == .folder, !node.isAggregate else { return node }
        let total = kept.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        return DiskNode(
            url: node.url, name: node.name, kind: node.kind, sizeBytes: total,
            modifiedAt: node.modifiedAt, children: kept,
            isAggregate: node.isAggregate, aggregateCount: node.aggregateCount
        )
    }

    /// 樹變動後,把 path 裁到仍存在的最深有效層。
    private mutating func clampPath() {
        var valid: [String] = []
        var node = root
        for id in path {
            guard let next = node.children.first(where: { $0.id == id && !$0.isAggregate }) else { break }
            valid.append(id)
            node = next
        }
        path = valid
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter DiskTreeNavigatorTests`
Expected: PASS(5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/GlanceCore/Sampling/DiskTreeNavigator.swift Tests/GlanceCoreTests/DiskTreeNavigatorTests.swift
git commit -m "feat: [core] 新增 DiskTreeNavigator 純導覽/移除/重算邏輯"
```

---

## Task 7: ViewModel 改寫(樹狀 + 快取 + 選取 + 刪除)

**Files:**
- Modify: `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift`(整檔改寫)

驗證方式:無 App 測試 target,以 `swift build` 確認編譯,行為於 Task 9 啟動驗證。

- [ ] **Step 1: 整檔覆寫 ViewModel**

```swift
import AppKit
import Combine
import Foundation
import GlanceCore

@MainActor
final class DiskSpaceAnalyzerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case completed
        case loadedFromCache
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var scannedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var currentPath: String?
    @Published private(set) var navigator: DiskTreeNavigator?
    @Published private(set) var lastScannedAt: Date?
    @Published var selection: Set<String> = []

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastPublishedAt: Date?
    private let analyzer: DiskSpaceAnalyzer
    private let cache: DiskScanCache
    private let trashService: DiskTrashService
    private let publishInterval: TimeInterval = 0.2

    init(
        analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer(),
        cache: DiskScanCache = DiskScanCache(),
        trashService: DiskTrashService = DiskTrashService()
    ) {
        self.analyzer = analyzer
        self.cache = cache
        self.trashService = trashService
    }

    deinit { scanTask?.cancel() }

    // MARK: - Derived state

    var isScanning: Bool { phase == .scanning }
    var currentNode: DiskNode? { navigator?.currentNode }
    var currentChildren: [DiskNode] { navigator?.currentNode.children ?? [] }
    var breadcrumb: [DiskNode] { navigator?.breadcrumb ?? [] }
    var currentFolderSize: UInt64 { navigator?.currentNode.sizeBytes ?? 0 }
    var canGoUp: Bool { navigator?.canGoUp ?? false }

    var selectedItems: [DiskNode] {
        currentChildren.filter { selection.contains($0.id) }
    }
    var selectedTotalBytes: UInt64 {
        selectedItems.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    var availableDiskBytes: UInt64 {
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    var statusText: String {
        switch phase {
        case .idle: return "準備掃描"
        case .scanning: return "掃描中…"
        case .completed: return "掃描完成"
        case .loadedFromCache: return "讀取自快取"
        case .cancelled: return "已取消"
        }
    }

    var lastScannedText: String? {
        guard let lastScannedAt else { return nil }
        return "上次掃描於 \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard phase == .idle else { return }
        if let entry = cache.load(rootURL: rootURL) {
            navigator = DiskTreeNavigator(root: entry.root)
            lastScannedAt = entry.scannedAt
            phase = .loadedFromCache
        } else {
            startScan()
        }
    }

    func startScan() {
        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        resetForScan()

        let root = rootURL
        scanTask = Task { [weak self, analyzer] in
            let result = await analyzer.scanTree(rootURL: root) { [weak self] progress in
                await self?.apply(progress, generation: generation)
            }
            await self?.apply(result, generation: generation)
        }
    }

    func cancelScan() { scanTask?.cancel() }

    func chooseRoot(_ url: URL) {
        rootURL = url
        selection = []
        navigator = nil
        phase = .idle
        onAppear()
    }

    // MARK: - Navigation

    func drill(into node: DiskNode) {
        guard var nav = navigator, node.isDrillable else { return }
        nav.drill(into: node)
        navigator = nav
        selection = []
    }

    func jump(toDepth depth: Int) {
        guard var nav = navigator else { return }
        nav.jump(toDepth: depth)
        navigator = nav
        selection = []
    }

    func goUp() {
        guard var nav = navigator else { return }
        nav.goUp()
        navigator = nav
        selection = []
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func clearSelection() { selection = [] }

    // MARK: - Trash

    func moveSelectedToTrash() {
        let items = selectedItems.map { DiskTrashRequestItem(url: $0.url, sizeBytes: $0.sizeBytes) }
        guard !items.isEmpty, let nav = navigator else { return }
        let root = rootURL
        let trashService = self.trashService

        Task { [weak self] in
            let result = await Task.detached { trashService.run(items: items, withinRoot: root) }.value
            await self?.applyTrashResult(result, requestedNavigator: nav)
        }
    }

    private func applyTrashResult(_ result: DiskTrashResult, requestedNavigator: DiskTreeNavigator) {
        guard var nav = navigator else { return }
        let trashedIDs = Set(
            selectedItems
                .filter { item in !result.skippedPaths.contains { $0.url == item.url } }
                .map(\.id)
        )
        nav.remove(ids: trashedIDs)
        navigator = nav
        selection = []
        persistCache(root: nav.root)
    }

    // MARK: - Helpers

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resetForScan() {
        phase = .scanning
        scannedCount = 0
        skippedCount = 0
        currentPath = nil
        navigator = nil
        selection = []
        lastPublishedAt = nil
    }

    private func apply(_ progress: DiskTreeScanProgress, generation: Int) {
        guard generation == scanGeneration, shouldPublish() else { return }
        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
    }

    private func apply(_ result: DiskTreeScanResult, generation: Int) {
        guard generation == scanGeneration else { return }
        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        scanTask = nil

        if result.state == .cancelled {
            phase = .cancelled
            return
        }
        if let root = result.root {
            navigator = DiskTreeNavigator(root: root)
            lastScannedAt = Date()
            persistCache(root: root)
        }
        phase = .completed
    }

    private func persistCache(root: DiskNode) {
        try? cache.save(root: root, rootURL: rootURL, scannedAt: lastScannedAt ?? Date())
    }

    private func shouldPublish() -> Bool {
        let now = Date()
        guard let lastPublishedAt else { self.lastPublishedAt = now; return true }
        if now.timeIntervalSince(lastPublishedAt) >= publishInterval {
            self.lastPublishedAt = now
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: 確認編譯**

Run: `swift build`
Expected: 編譯成功(可能因 Window 仍引用舊 API 而有錯,將於 Task 9 一併修正;若此時 Window 尚未改,允許編譯錯誤集中在 `DiskSpaceAnalyzerWindow.swift`)。

> 註:若採 subagent 逐任務,建議 Task 7→8→9 連續完成後再整體 `swift build`,避免中間態編譯失敗。Commit 仍各自進行。

- [ ] **Step 3: Commit**

```bash
git add GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift
git commit -m "feat: [app] DiskSpaceAnalyzer ViewModel 改為樹狀導覽 + 快取 + 選取刪除"
```

---

## Task 8: Bento UI 元件

**Files:**
- Create: `GlanceApp/DiskAnalyzer/Components/ScanSummaryStrip.swift`
- Create: `GlanceApp/DiskAnalyzer/Components/BreadcrumbBar.swift`
- Create: `GlanceApp/DiskAnalyzer/Components/DiskNodeRow.swift`
- Create: `GlanceApp/DiskAnalyzer/Components/TrashActionBar.swift`

- [ ] **Step 1: ScanSummaryStrip(Bento 摘要列)**

建立 `GlanceApp/DiskAnalyzer/Components/ScanSummaryStrip.swift`:

```swift
import SwiftUI

struct ScanSummaryStrip: View {
    let folderSize: String
    let itemCount: Int
    let selectedCount: Int
    let selectedSize: String
    let availableSize: String

    var body: some View {
        HStack(spacing: 10) {
            tile("目前資料夾", folderSize, accent: false)
            tile("項目數", "\(itemCount)", accent: false)
            tile("已選取", selectedCount == 0 ? "—" : "\(selectedCount) 項 · \(selectedSize)", accent: selectedCount > 0)
            tile("磁碟可用", availableSize, accent: false)
        }
    }

    private func tile(_ title: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
```

- [ ] **Step 2: BreadcrumbBar(可點跳層麵包屑)**

建立 `GlanceApp/DiskAnalyzer/Components/BreadcrumbBar.swift`:

```swift
import SwiftUI
import GlanceCore

struct BreadcrumbBar: View {
    let nodes: [DiskNode]            // root...current
    let onJump: (Int) -> Void        // depth: 0 = root

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onJump(index)
                    } label: {
                        Text(node.name)
                            .font(.system(size: 11, weight: index == nodes.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == nodes.count - 1 ? Color.primary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 3: DiskNodeRow(清單列:勾選 + 圖示 + 佔比 + 大小 + 動作)**

建立 `GlanceApp/DiskAnalyzer/Components/DiskNodeRow.swift`:

```swift
import SwiftUI
import GlanceCore

struct DiskNodeRow: View {
    let node: DiskNode
    let fraction: Double            // node.sizeBytes / 父資料夾總大小
    let isSelected: Bool
    let onToggle: () -> Void
    let onDrill: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            checkbox
            icon
            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)

            ProgressView(value: max(0, min(1, fraction)))
                .progressViewStyle(.linear)
                .tint(node.kind == .folder ? Color.accentColor : Color.gray)

            Text(Formatters.bytes(node.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            Text(modifiedText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

            Button(action: onDrill) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .opacity(node.isDrillable ? 1 : 0)
            .disabled(!node.isDrillable)

            Button(action: onReveal) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .opacity(node.isAggregate ? 0 : 1)
            .disabled(node.isAggregate)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.red.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if node.isDrillable { onDrill() } }
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.red : Color.secondary)
        }
        .buttonStyle(.borderless)
        .opacity(node.isAggregate ? 0.25 : 1)
        .disabled(node.isAggregate)
    }

    private var icon: some View {
        Image(systemName: node.isAggregate ? "ellipsis.circle" : (node.kind == .folder ? "folder.fill" : "doc.fill"))
            .font(.system(size: 13))
            .foregroundStyle(node.kind == .folder && !node.isAggregate ? Color.accentColor : Color.secondary)
            .frame(width: 16)
    }

    private var modifiedText: String {
        guard let modifiedAt = node.modifiedAt else { return "" }
        return modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
```

- [ ] **Step 4: TrashActionBar(底部刪除列)**

建立 `GlanceApp/DiskAnalyzer/Components/TrashActionBar.swift`:

```swift
import SwiftUI

struct TrashActionBar: View {
    let selectedCount: Int
    let selectedSize: String
    let onTrash: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if selectedCount == 0 {
                Text("勾選項目以移到垃圾桶(可在 Finder 還原)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("已選取 \(selectedCount) 項,共 \(selectedSize) — 將移到垃圾桶(可在 Finder 還原)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清除選取", action: onClear)
                    .buttonStyle(.borderless)
                Button(role: .destructive, action: onTrash) {
                    Label("移到垃圾桶", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add GlanceApp/DiskAnalyzer/Components/
git commit -m "feat: [app] 新增磁碟分析 Bento UI 元件(摘要列/麵包屑/清單列/刪除列)"
```

---

## Task 9: Window 改寫(組裝 + 選資料夾 + 確認對話框)

**Files:**
- Modify: `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift`(整檔改寫)
- Modify: `GlanceApp/GlanceApp.swift:16`(視窗標題)

- [ ] **Step 1: 整檔覆寫 Window**

```swift
import AppKit
import SwiftUI
import GlanceCore

struct DiskSpaceAnalyzerWindow: View {
    @StateObject private var viewModel = DiskSpaceAnalyzerViewModel()
    @State private var showTrashConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            if viewModel.navigator != nil { breadcrumb }
            content
            TrashActionBar(
                selectedCount: viewModel.selection.count,
                selectedSize: Formatters.bytes(viewModel.selectedTotalBytes),
                onTrash: { showTrashConfirm = true },
                onClear: viewModel.clearSelection
            )
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 540)
        .onAppear { viewModel.onAppear() }
        .confirmationDialog(
            "移到垃圾桶?",
            isPresented: $showTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("移到垃圾桶(\(viewModel.selection.count) 項)", role: .destructive) {
                viewModel.moveSelectedToTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("將把所選 \(viewModel.selection.count) 項(共 \(Formatters.bytes(viewModel.selectedTotalBytes)))移到垃圾桶,可在 Finder 還原。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("磁碟空間分析")
                    .font(.system(size: 20, weight: .semibold))
                Text(viewModel.rootURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    chooseRoot()
                } label: {
                    Label("選擇資料夾…", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    if viewModel.isScanning { viewModel.cancelScan() } else { viewModel.startScan() }
                } label: {
                    Label(
                        viewModel.isScanning ? "取消" : "重新掃描",
                        systemImage: viewModel.isScanning ? "xmark.circle" : "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summary: some View {
        ScanSummaryStrip(
            folderSize: Formatters.bytes(viewModel.currentFolderSize),
            itemCount: viewModel.currentChildren.count,
            selectedCount: viewModel.selection.count,
            selectedSize: Formatters.bytes(viewModel.selectedTotalBytes),
            availableSize: Formatters.bytes(viewModel.availableDiskBytes)
        )
    }

    private var breadcrumb: some View {
        BreadcrumbBar(nodes: viewModel.breadcrumb) { depth in
            viewModel.jump(toDepth: depth)
        }
    }

    private var content: some View {
        let parentSize = max(viewModel.currentFolderSize, 1)
        return List(viewModel.currentChildren) { node in
            DiskNodeRow(
                node: node,
                fraction: Double(node.sizeBytes) / Double(parentSize),
                isSelected: viewModel.selection.contains(node.id),
                onToggle: { viewModel.toggleSelection(node.id) },
                onDrill: { viewModel.drill(into: node) },
                onReveal: { viewModel.reveal(node.url) }
            )
            .listRowInsets(EdgeInsets())
        }
        .overlay {
            if viewModel.currentChildren.isEmpty {
                Text(viewModel.isScanning ? "掃描中…" : "沒有項目")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLine: String {
        if viewModel.isScanning {
            return viewModel.currentPath ?? "掃描中…(已掃描 \(viewModel.scannedCount))"
        }
        if let last = viewModel.lastScannedText { return last }
        return viewModel.statusText
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.chooseRoot(url)
        }
    }
}
```

- [ ] **Step 2: 更新視窗標題**

修改 `GlanceApp/GlanceApp.swift` 第 16 行:

```swift
        Window("磁碟空間分析", id: "disk-space-analyzer") {
```

- [ ] **Step 3: 整體建置**

Run: `swift build`
Expected: 編譯成功,無錯誤。

- [ ] **Step 4: Commit**

```bash
git add GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift GlanceApp/GlanceApp.swift
git commit -m "feat: [app] 磁碟分析視窗改寫:樹狀下鑽 + 選資料夾 + 刪除確認"
```

---

## Task 10: 清理死碼、全測試與啟動驗證

**Files:**
- Modify: `Sources/GlanceCore/Model/DiskSpaceItem.swift`(移除改寫後未用的平面型別)
- Modify: `GlanceApp/Dropdown/DiskSection.swift`(確認「分析空間…」按鈕標籤,如需)

- [ ] **Step 1: 確認舊平面型別已無引用**

Run:
```bash
grep -rn "DiskSpaceScanResult\|DiskSpaceScanProgress\|largestFolders\|largestFiles\|DiskSpaceItem(" Sources GlanceApp Tests
```
Expected: 僅可能出現在 `DiskSpaceItem.swift` 定義處。若其他檔仍引用,表示前面任務遺漏,先修正再繼續。

- [ ] **Step 2: 移除死碼**

編輯 `Sources/GlanceCore/Model/DiskSpaceItem.swift`,移除 `DiskSpaceItem`、`DiskSpaceScanProgress`、`DiskSpaceScanResult` 三個 struct,**保留** `DiskSpaceItemKind`、`DiskSpaceSkippedPath`、`DiskSpaceScanState`(仍被 DiskNode / Uninstaller / 新結果型別使用)。

保留後的檔案內容:

```swift
import Foundation

public enum DiskSpaceItemKind: Equatable, Sendable, Codable {
    case file
    case folder
}

public struct DiskSpaceSkippedPath: Equatable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.id = url.path
        self.url = url
        self.reason = reason
    }
}

public enum DiskSpaceScanState: Equatable, Sendable {
    case running
    case completed
    case cancelled
}
```

- [ ] **Step 3: 全測試**

Run: `swift test --filter GlanceCoreTests`
Expected: 全部通過(含新增的 DiskNode/DiskSpaceAnalyzer/DiskScanCache/DiskTrashSafety/DiskTrashService/DiskTreeNavigator 測試)。

- [ ] **Step 4: 全建置**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 5: 啟動驗證(手動)**

依專案慣例組 .app 並啟動(見 memory「Glance Homebrew 打包」),從選單列 Disk 卡片點「分析空間…」開啟視窗,逐項確認:
- 首次開啟自動掃描家目錄;完成後標頭顯示「上次掃描於 …」
- 關閉再開:讀快取秒開(phase = loadedFromCache)
- 點資料夾列或 chevron 可下鑽;麵包屑可跳回上層;佔比長條依大小呈現
- 長尾顯示為「其他 N 個項目」,不可勾選/下鑽
- 勾選數項 → 底部出現刪除列 → 「移到垃圾桶」跳確認 → 確認後項目消失、上層大小重算、可在 Finder 垃圾桶看到
- 「選擇資料夾…」可改掃其他目錄

- [ ] **Step 6: Commit**

```bash
git add Sources/GlanceCore/Model/DiskSpaceItem.swift
git commit -m "refactor: [core] 移除磁碟分析改寫後未用的平面型別"
```

---

## 自我檢查紀錄

- **Spec 覆蓋**:樹模型(T1)、並行建樹+長尾聚合(T2)、快取(T3)、護欄(T4)+執行(T5)、導覽/移除重算(T6)、ViewModel(T7)、Bento UI 含麵包屑/佔比/摘要/刪除列(T8)、視窗組裝+選資料夾+確認(T9)、死碼清理+全驗證(T10)。全數對應。
- **型別一致性**:`scanTree`/`DiskTreeScanResult.root`/`DiskTreeScanProgress`、`DiskTreeNavigator.drill/jump/goUp/remove`、`DiskTrashRequestItem`/`DiskTrashResult`、`DiskScanCacheEntry` 命名在各任務間一致。
- **無 placeholder**:每個程式步驟皆含完整程式碼與預期輸出。
- **已知取捨**:T7 ViewModel 改寫後、T9 視窗改寫前,`DiskSpaceAnalyzerWindow.swift` 會暫時編譯失敗(仍用舊 API),已於 T7 Step 2 註明;逐任務執行者請連續完成 T7→T9 後再整體建置。
