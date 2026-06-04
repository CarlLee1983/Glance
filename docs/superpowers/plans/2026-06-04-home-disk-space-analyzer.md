# Home Disk Space Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-demand, read-only Glance window that scans the user's home directory and ranks the largest folders and files.

**Architecture:** Put traversal, ranking, progress, and cancellation in `GlanceCore` so it can be unit tested with temporary directories. Keep window presentation and Finder reveal in `GlanceApp`, with the Disk dropdown only opening the tool and never running the scan itself.

**Tech Stack:** Swift 5.9, Swift concurrency, SwiftUI, AppKit Finder reveal, XCTest, existing `GlanceCore` package and `Glance` XcodeGen app target.

---

## File Structure

- Create `Sources/GlanceCore/Model/DiskSpaceItem.swift`
  - Read-only value models for scan items, skipped paths, progress, and final result.
- Create `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift`
  - Async recursive traversal, top-N ranking, skipped path capture, cancellation checks, and progress emission.
- Create `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`
  - Temporary-directory tests for ranking, nested folder sizes, hidden files, symlink handling, skipped paths, and cancellation.
- Create `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift`
  - Main-actor app state wrapper that starts, cancels, throttles progress, and stores results for SwiftUI.
- Create `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift`
  - SwiftUI utility window with progress header, segmented results, result rows, cancel/rescan, and Reveal in Finder action.
- Modify `GlanceApp/GlanceApp.swift`
  - Add a `Window("Disk Space Analyzer", id: "disk-space-analyzer")` scene.
- Modify `GlanceApp/Dropdown/DiskSection.swift`
  - Add an "Analyze Space..." button and open the analyzer window.
- Modify `project.yml`
  - No source path change is required because `GlanceApp` is already included recursively; only modify if XcodeGen output shows the new folder is not picked up.
- Modify `README.md`
  - Add a short note that Disk can open a read-only analyzer window.

---

### Task 1: Add Core Models And Failing Tests

**Files:**
- Create: `Sources/GlanceCore/Model/DiskSpaceItem.swift`
- Create: `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`

- [ ] **Step 1: Add the core value models**

Create `Sources/GlanceCore/Model/DiskSpaceItem.swift`:

```swift
import Foundation

public enum DiskSpaceItemKind: Equatable, Sendable {
    case file
    case folder
}

public struct DiskSpaceItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let name: String
    public let sizeBytes: UInt64
    public let kind: DiskSpaceItemKind
    public let modifiedAt: Date?

    public init(url: URL, sizeBytes: UInt64, kind: DiskSpaceItemKind, modifiedAt: Date?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.modifiedAt = modifiedAt
    }
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

public struct DiskSpaceScanProgress: Equatable, Sendable {
    public let scannedCount: Int
    public let skippedCount: Int
    public let currentPath: String?
    public let largestFolders: [DiskSpaceItem]
    public let largestFiles: [DiskSpaceItem]

    public init(
        scannedCount: Int,
        skippedCount: Int,
        currentPath: String?,
        largestFolders: [DiskSpaceItem],
        largestFiles: [DiskSpaceItem]
    ) {
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.currentPath = currentPath
        self.largestFolders = largestFolders
        self.largestFiles = largestFiles
    }
}

public struct DiskSpaceScanResult: Equatable, Sendable {
    public let rootURL: URL
    public let state: DiskSpaceScanState
    public let scannedCount: Int
    public let largestFolders: [DiskSpaceItem]
    public let largestFiles: [DiskSpaceItem]
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(
        rootURL: URL,
        state: DiskSpaceScanState,
        scannedCount: Int,
        largestFolders: [DiskSpaceItem],
        largestFiles: [DiskSpaceItem],
        skippedPaths: [DiskSpaceSkippedPath]
    ) {
        self.rootURL = rootURL
        self.state = state
        self.scannedCount = scannedCount
        self.largestFolders = largestFolders
        self.largestFiles = largestFiles
        self.skippedPaths = skippedPaths
    }
}
```

- [ ] **Step 2: Write failing analyzer tests**

Create `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`:

```swift
import XCTest
@testable import GlanceCore

final class DiskSpaceAnalyzerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRanksLargestFilesDescending() async throws {
        let root = try makeTemporaryRoot()
        try writeFile(root.appendingPathComponent("small.bin"), byteCount: 10)
        try writeFile(root.appendingPathComponent("large.bin"), byteCount: 40)
        try writeFile(root.appendingPathComponent("medium.bin"), byteCount: 20)

        let result = await DiskSpaceAnalyzer(maxResults: 2).scan(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.largestFiles.map(\.name), ["large.bin", "medium.bin"])
        XCTAssertEqual(result.largestFiles.map(\.sizeBytes), [40, 20])
    }

    func testFolderSizesIncludeNestedChildren() async throws {
        let root = try makeTemporaryRoot()
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try writeFile(parent.appendingPathComponent("one.dat"), byteCount: 15)
        try writeFile(child.appendingPathComponent("two.dat"), byteCount: 25)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        let parentItem = try XCTUnwrap(result.largestFolders.first { $0.url == parent })
        let childItem = try XCTUnwrap(result.largestFolders.first { $0.url == child })
        XCTAssertEqual(parentItem.sizeBytes, 40)
        XCTAssertEqual(childItem.sizeBytes, 25)
    }

    func testIncludesHiddenDirectories() async throws {
        let root = try makeTemporaryRoot()
        let hidden = root.appendingPathComponent(".cache", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(hidden.appendingPathComponent("cache.dat"), byteCount: 33)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertTrue(result.largestFolders.contains { $0.url == hidden && $0.sizeBytes == 33 })
        XCTAssertTrue(result.largestFiles.contains { $0.name == "cache.dat" && $0.sizeBytes == 33 })
    }

    func testDoesNotFollowSymlinks() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        try writeFile(outside.appendingPathComponent("outside.dat"), byteCount: 99)
        let symlink = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertFalse(result.largestFiles.contains { $0.name == "outside.dat" })
        XCTAssertFalse(result.largestFolders.contains { $0.url.path.contains(outside.path) })
    }

    func testMissingRootIsSkippedWithoutFailingScan() async throws {
        let root = try makeTemporaryRoot()
        try FileManager.default.removeItem(at: root)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.scannedCount, 0)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, root)
    }

    func testCancellationReturnsCancelledState() async throws {
        let root = try makeTemporaryRoot()
        for index in 0..<200 {
            try writeFile(root.appendingPathComponent("file-\(index).dat"), byteCount: 1)
        }

        let analyzer = DiskSpaceAnalyzer(maxResults: 10)
        let task = Task {
            await analyzer.scan(rootURL: root) { _ in
                Task.cancel()
            }
        }
        let result = await task.value

        XCTAssertEqual(result.state, .cancelled)
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
```

- [ ] **Step 3: Run tests to verify analyzer implementation is missing**

Run:

```bash
swift test --filter DiskSpaceAnalyzerTests
```

Expected: build fails because `DiskSpaceAnalyzer` is not defined.

- [ ] **Step 4: Commit models and failing tests**

```bash
git add Sources/GlanceCore/Model/DiskSpaceItem.swift Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift
git commit -m "Define why disk analyzer core needs testable models" -m "Constraint: Scan behavior must be covered in GlanceCore before app UI is wired.\nConfidence: high\nScope-risk: narrow\nTested: swift test --filter DiskSpaceAnalyzerTests fails because DiskSpaceAnalyzer is not implemented.\nNot-tested: Runtime scanning is not implemented yet."
```

---

### Task 2: Implement DiskSpaceAnalyzer Core

**Files:**
- Create: `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift`
- Modify: `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift`

- [ ] **Step 1: Implement the analyzer**

Create `Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift`:

```swift
import Foundation

public final class DiskSpaceAnalyzer: Sendable {
    public typealias ProgressHandler = @Sendable (DiskSpaceScanProgress) async -> Void

    private let maxResults: Int
    private let fileManager: FileManager

    public init(maxResults: Int = 50, fileManager: FileManager = .default) {
        self.maxResults = max(1, maxResults)
        self.fileManager = fileManager
    }

    public func scan(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: ProgressHandler? = nil
    ) async -> DiskSpaceScanResult {
        var state = ScanAccumulator(rootURL: rootURL, maxResults: maxResults)
        _ = await scanDirectory(rootURL, state: &state, progress: progress)
        return state.result(cancelled: Task.isCancelled)
    }

    private func scanDirectory(
        _ url: URL,
        state: inout ScanAccumulator,
        progress: ProgressHandler?
    ) async -> UInt64 {
        if Task.isCancelled { return 0 }

        var isDirectoryValue: AnyObject?
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectoryValue) else {
            state.skip(url, reason: "Path does not exist")
            await emitProgress(state, currentURL: url, progress: progress)
            return 0
        }

        guard (isDirectoryValue as? NSNumber)?.boolValue == true else {
            return await scanFile(url, state: &state, progress: progress)
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
        if resourceValues?.isSymbolicLink == true {
            state.skip(url, reason: "Symbolic link skipped")
            await emitProgress(state, currentURL: url, progress: progress)
            return 0
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else {
            state.skip(url, reason: "Directory is not readable")
            await emitProgress(state, currentURL: url, progress: progress)
            return 0
        }

        state.scannedCount += 1
        await emitProgress(state, currentURL: url, progress: progress)

        var total: UInt64 = 0
        for child in children {
            if Task.isCancelled { break }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            if values?.isSymbolicLink == true {
                state.skip(child, reason: "Symbolic link skipped")
                continue
            }
            if values?.isDirectory == true {
                total += await scanDirectory(child, state: &state, progress: progress)
            } else if values?.isRegularFile == true {
                total += await scanFile(child, state: &state, progress: progress, values: values)
            } else {
                state.skip(child, reason: "Unsupported file type")
            }
        }

        state.recordFolder(url: url, sizeBytes: total, modifiedAt: resourceValues?.contentModificationDate)
        await emitProgress(state, currentURL: url, progress: progress)
        return total
    }

    private func scanFile(
        _ url: URL,
        state: inout ScanAccumulator,
        progress: ProgressHandler?,
        values: URLResourceValues? = nil
    ) async -> UInt64 {
        if Task.isCancelled { return 0 }

        let resourceValues = values ?? (try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]))
        guard resourceValues?.isRegularFile == true else {
            state.skip(url, reason: "Unsupported file type")
            await emitProgress(state, currentURL: url, progress: progress)
            return 0
        }

        let size = UInt64(resourceValues?.fileSize ?? 0)
        state.scannedCount += 1
        state.recordFile(url: url, sizeBytes: size, modifiedAt: resourceValues?.contentModificationDate)
        await emitProgress(state, currentURL: url, progress: progress)
        return size
    }

    private func emitProgress(
        _ state: ScanAccumulator,
        currentURL: URL,
        progress: ProgressHandler?
    ) async {
        guard let progress else { return }
        await progress(state.progress(currentPath: currentURL.path))
    }
}

private struct ScanAccumulator {
    let rootURL: URL
    let maxResults: Int
    var scannedCount = 0
    var largestFolders: [DiskSpaceItem] = []
    var largestFiles: [DiskSpaceItem] = []
    var skippedPaths: [DiskSpaceSkippedPath] = []

    mutating func recordFile(url: URL, sizeBytes: UInt64, modifiedAt: Date?) {
        insert(DiskSpaceItem(url: url, sizeBytes: sizeBytes, kind: .file, modifiedAt: modifiedAt), into: &largestFiles)
    }

    mutating func recordFolder(url: URL, sizeBytes: UInt64, modifiedAt: Date?) {
        insert(DiskSpaceItem(url: url, sizeBytes: sizeBytes, kind: .folder, modifiedAt: modifiedAt), into: &largestFolders)
    }

    mutating func skip(_ url: URL, reason: String) {
        skippedPaths.append(DiskSpaceSkippedPath(url: url, reason: reason))
    }

    func progress(currentPath: String?) -> DiskSpaceScanProgress {
        DiskSpaceScanProgress(
            scannedCount: scannedCount,
            skippedCount: skippedPaths.count,
            currentPath: currentPath,
            largestFolders: largestFolders,
            largestFiles: largestFiles
        )
    }

    func result(cancelled: Bool) -> DiskSpaceScanResult {
        DiskSpaceScanResult(
            rootURL: rootURL,
            state: cancelled ? .cancelled : .completed,
            scannedCount: scannedCount,
            largestFolders: largestFolders,
            largestFiles: largestFiles,
            skippedPaths: skippedPaths
        )
    }

    private mutating func insert(_ item: DiskSpaceItem, into items: inout [DiskSpaceItem]) {
        items.append(item)
        items.sort {
            if $0.sizeBytes == $1.sizeBytes {
                return $0.url.path < $1.url.path
            }
            return $0.sizeBytes > $1.sizeBytes
        }
        if items.count > maxResults {
            items.removeLast(items.count - maxResults)
        }
    }
}
```

- [ ] **Step 2: Adjust the cancellation test to cancel the scan task directly**

Replace `testCancellationReturnsCancelledState` in `Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift` with:

```swift
    func testCancellationReturnsCancelledState() async throws {
        let root = try makeTemporaryRoot()
        for index in 0..<200 {
            try writeFile(root.appendingPathComponent("file-\(index).dat"), byteCount: 1)
        }

        let analyzer = DiskSpaceAnalyzer(maxResults: 10)
        var scanTask: Task<DiskSpaceScanResult, Never>!
        scanTask = Task {
            await analyzer.scan(rootURL: root) { progress in
                if progress.scannedCount > 0 {
                    scanTask.cancel()
                }
            }
        }
        let result = await scanTask.value

        XCTAssertEqual(result.state, .cancelled)
    }
```

- [ ] **Step 3: Run analyzer tests**

Run:

```bash
swift test --filter DiskSpaceAnalyzerTests
```

Expected: all `DiskSpaceAnalyzerTests` pass.

- [ ] **Step 4: Run the full core test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit analyzer core**

```bash
git add Sources/GlanceCore/Sampling/DiskSpaceAnalyzer.swift Tests/GlanceCoreTests/DiskSpaceAnalyzerTests.swift
git commit -m "Keep disk space traversal read-only and testable" -m "Constraint: Analyzer must not depend on SwiftUI or AppKit.\nRejected: Finder reveal in GlanceCore | Reveal is an app concern and would pollute the package boundary.\nConfidence: high\nScope-risk: moderate\nTested: swift test --filter DiskSpaceAnalyzerTests; swift test\nNot-tested: Real home-directory scan performance is verified in a later app task."
```

---

### Task 3: Add App View Model

**Files:**
- Create: `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift`

- [ ] **Step 1: Create the main-actor view model**

Create `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift`:

```swift
import Foundation
import GlanceCore

@MainActor
final class DiskSpaceAnalyzerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case completed
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var scannedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var currentPath: String?
    @Published private(set) var largestFolders: [DiskSpaceItem] = []
    @Published private(set) var largestFiles: [DiskSpaceItem] = []
    @Published private(set) var skippedPaths: [DiskSpaceSkippedPath] = []

    private var scanTask: Task<Void, Never>?
    private let analyzer: DiskSpaceAnalyzer

    init(analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer(maxResults: 50)) {
        self.analyzer = analyzer
    }

    var isScanning: Bool {
        phase == .scanning
    }

    var statusText: String {
        switch phase {
        case .idle:
            return "Ready to scan your home directory"
        case .scanning:
            return "Scanning..."
        case .completed:
            return "Scan complete"
        case .cancelled:
            return "Scan cancelled"
        }
    }

    func startScan() {
        scanTask?.cancel()
        resetForScan()

        let root = rootURL
        scanTask = Task { [analyzer] in
            let result = await analyzer.scan(rootURL: root) { [weak self] progress in
                await self?.apply(progress)
            }
            await apply(result)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func resetForScan() {
        phase = .scanning
        scannedCount = 0
        skippedCount = 0
        currentPath = nil
        largestFolders = []
        largestFiles = []
        skippedPaths = []
    }

    private func apply(_ progress: DiskSpaceScanProgress) {
        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
        largestFolders = progress.largestFolders
        largestFiles = progress.largestFiles
    }

    private func apply(_ result: DiskSpaceScanResult) {
        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        largestFolders = result.largestFolders
        largestFiles = result.largestFiles
        skippedPaths = result.skippedPaths
        phase = result.state == .cancelled ? .cancelled : .completed
        scanTask = nil
    }
}
```

- [ ] **Step 2: Build the app target**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 3: Commit the view model**

```bash
git add GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerViewModel.swift Glance.xcodeproj
git commit -m "Separate disk analyzer app state from traversal" -m "Constraint: SwiftUI should observe a main-actor model while scanning stays off the main actor.\nConfidence: high\nScope-risk: narrow\nTested: xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build\nNot-tested: Window UI is added in the next task."
```

---

### Task 4: Add Analyzer Window UI And Disk Entry Point

**Files:**
- Create: `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift`
- Modify: `GlanceApp/GlanceApp.swift`
- Modify: `GlanceApp/Dropdown/DiskSection.swift`
- Modify: `README.md`

- [ ] **Step 1: Create the analyzer window**

Create `GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift`:

```swift
import AppKit
import SwiftUI
import GlanceCore

struct DiskSpaceAnalyzerWindow: View {
    @StateObject private var viewModel = DiskSpaceAnalyzerViewModel()
    @State private var selectedView: ResultView = .folders

    enum ResultView: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case files = "Files"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summary
            Picker("Results", selection: $selectedView) {
                ForEach(ResultView.allCases) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.segmented)
            resultList
            footer
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if viewModel.phase == .idle {
                viewModel.startScan()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Space Analyzer")
                    .font(.system(size: 20, weight: .semibold))
                Text(viewModel.rootURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let currentPath = viewModel.currentPath {
                    Text(currentPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button {
                viewModel.isScanning ? viewModel.cancelScan() : viewModel.startScan()
            } label: {
                Label(viewModel.isScanning ? "Cancel" : "Rescan", systemImage: viewModel.isScanning ? "xmark.circle" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            summaryTile("Status", viewModel.statusText)
            summaryTile("Scanned", "\(viewModel.scannedCount)")
            summaryTile("Skipped", "\(viewModel.skippedCount)")
            summaryTile("Visible", "\(currentItems.count)")
        }
    }

    private func summaryTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var resultList: some View {
        List(currentItems) { item in
            HStack(spacing: 12) {
                Image(systemName: item.kind == .folder ? "folder" : "doc")
                    .foregroundStyle(item.kind == .folder ? .blue : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(item.url.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.bytes(item.sizeBytes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let modifiedAt = item.modifiedAt {
                        Text(modifiedAt, style: .date)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, alignment: .trailing)

                Button {
                    reveal(item.url)
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if currentItems.isEmpty {
                Text(viewModel.isScanning ? "Scanning..." : "No results")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(viewModel.skippedCount == 0 ? "No skipped paths" : "\(viewModel.skippedCount) paths skipped")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Read-only: no files are deleted or moved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var currentItems: [DiskSpaceItem] {
        selectedView == .folders ? viewModel.largestFolders : viewModel.largestFiles
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
```

- [ ] **Step 2: Add a window scene**

Modify `GlanceApp/GlanceApp.swift` to:

```swift
import SwiftUI
import GlanceCore

@main
struct GlanceApp: App {
    @StateObject private var store = MetricsStore(sampler: SystemSampler())

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Disk Space Analyzer", id: "disk-space-analyzer") {
            DiskSpaceAnalyzerWindow()
        }

        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 3: Add the Disk dropdown entry point**

Modify `GlanceApp/Dropdown/DiskSection.swift` to:

```swift
import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        MetricCard(
            title: "磁碟",
            systemImage: "internaldrive",
            accent: .yellow,
            value: Formatters.percent(usedFraction),
            detail: diskDetail,
            status: MetricStatus.capacity(fraction: usedFraction)
        ) {
            CustomProgressBar(value: usedFraction, color: .yellow)

            Button {
                openAnalyzerWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                    Text("分析空間...")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.yellow.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private var diskDetail: String {
        guard let d = snapshot else { return "等待磁碟取樣" }
        return "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes))"
    }

    private func openAnalyzerWindow() {
        openWindow(id: "disk-space-analyzer")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 4: Document the new Disk feature**

Add this paragraph under the `## 選單列 App(GlanceApp)` feature list in `README.md`:

```markdown
- **磁碟空間分析**: 磁碟區塊可開啟唯讀分析視窗,按需掃描家目錄並列出最大資料夾與最大檔案;第一版只提供 Finder 中顯示,不刪除或移動檔案。
```

- [ ] **Step 5: Generate and build**

Run:

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 6: Commit the UI integration**

```bash
git add GlanceApp/DiskAnalyzer/DiskSpaceAnalyzerWindow.swift GlanceApp/GlanceApp.swift GlanceApp/Dropdown/DiskSection.swift README.md Glance.xcodeproj
git commit -m "Expose read-only disk analysis from Glance" -m "Constraint: The menu bar dropdown stays compact and only opens an on-demand utility window.\nRejected: Show scan results directly in the dropdown | Full results would make the dropdown heavy and hard to scan.\nConfidence: high\nScope-risk: moderate\nTested: xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build\nNot-tested: Manual Finder reveal and real home scan are verified in final QA."
```

---

### Task 5: Final Verification And Polish

**Files:**
- Modify only files touched by earlier tasks if verification finds defects.

- [ ] **Step 1: Run package tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `Glance.xcodeproj` is updated or remains unchanged without errors.

- [ ] **Step 3: Build the app**

Run:

```bash
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 4: Manually verify the analyzer window**

Run the built app from Xcode or the build product, then verify:

- The Glance dropdown still opens quickly.
- The Disk section shows "分析空間...".
- Clicking it opens "Disk Space Analyzer".
- The analyzer starts scanning only after the window opens.
- The window shows progress while scanning.
- Folders and Files segmented views both populate.
- Reveal works for one folder and one file.
- Cancel stops an active scan.
- Rescan starts a new scan.
- No delete, trash, or cleanup action exists.

- [ ] **Step 5: Inspect the final diff**

Run:

```bash
git diff --stat HEAD
git diff HEAD -- Sources GlanceApp Tests README.md Package.swift project.yml
```

Expected: changes are limited to disk analyzer core, tests, app UI, README, and generated Xcode project updates.

- [ ] **Step 6: Commit verification fixes if needed**

If Step 4 or Step 5 required fixes, commit them:

```bash
git add Sources GlanceApp Tests README.md Glance.xcodeproj
git commit -m "Stabilize disk analyzer verification path" -m "Constraint: Final fixes must preserve read-only behavior and on-demand scanning.\nConfidence: high\nScope-risk: narrow\nTested: swift test; xcodegen generate; xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build; manual analyzer smoke test\nNot-tested: Long-duration scans on very large home directories."
```

If no fixes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Disk entry point: Task 4, Steps 2-3.
- Separate analyzer window: Task 4, Step 1.
- Home-only on-demand scan: Task 2 scan default and Task 4 window `onAppear`.
- Largest folders and files: Tasks 1-2 models/tests and Task 4 segmented UI.
- Progress, skipped paths, completion state: Tasks 1-3 models/view model and Task 4 summary/footer.
- Reveal in Finder: Task 4, Step 1.
- Read-only boundary: Task 4 footer and no delete/trash APIs in any task.
- Responsiveness: Task 2 off-main async scan and Task 3 task-based view model.
- Core tests: Tasks 1-2.

Placeholder scan:

- No unresolved placeholder markers or unspecified edge handling remain.

Type consistency:

- `DiskSpaceItem`, `DiskSpaceScanProgress`, `DiskSpaceScanResult`, `DiskSpaceSkippedPath`, and `DiskSpaceAnalyzer` signatures are consistent across test, core, view model, and UI tasks.
