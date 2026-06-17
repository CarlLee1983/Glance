import Foundation

/// Streaming 磁碟掃描器:子樹遞迴序列掃描,由下往上彙總每層大小,
/// 但每層只保留 top-K children 與有限深度的可瀏覽樹,避免 home 目錄全樹常駐記憶體。
/// 安全性不變式:無可變儲存屬性(只有 let),狀態彙整集中於 ScanReporter actor。
public final class DiskSpaceAnalyzer: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (DiskTreeScanProgress) async -> Void

    private let keepTopPerFolder: Int
    private let retainedDepth: Int
    private let fileManager: FileManager

    public init(keepTopPerFolder: Int = 100, retainedDepth: Int = 2, fileManager: FileManager = .default) {
        self.keepTopPerFolder = max(1, keepTopPerFolder)
        self.retainedDepth = max(0, retainedDepth)
        self.fileManager = fileManager
    }

    public func scanTree(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: ProgressHandler? = nil
    ) async -> DiskTreeScanResult {
        let reporter = ScanReporter(progress: progress)
        let builder = TreeBuilder(
            fileManager: fileManager,
            keepTopPerFolder: keepTopPerFolder,
            retainedDepth: retainedDepth,
            reporter: reporter
        )
        let root = await builder.build(url: rootURL, depth: 0)
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
    let retainedDepth: Int
    let reporter: ScanReporter

    init(fileManager: FileManager, keepTopPerFolder: Int, retainedDepth: Int, reporter: ScanReporter) {
        self.fileManager = fileManager
        self.keepTopPerFolder = keepTopPerFolder
        self.retainedDepth = retainedDepth
        self.reporter = reporter
    }

    func build(url: URL, depth: Int) async -> DiskNode? {
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
            return await buildDirectory(url, depth: depth)
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

    private func buildDirectory(_ url: URL, depth: Int) async -> DiskNode? {
        let directoryValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])

        await reporter.didScan(url.path)

        guard depth < retainedDepth else {
            let total = await summarizeChildren(of: url)
            return DiskNode(
                url: url, kind: .folder, sizeBytes: total,
                modifiedAt: directoryValues?.contentModificationDate
            )
        }

        guard let enumerator = immediateChildren(of: url) else {
            await reporter.didSkip(url, reason: "Directory is not readable")
            return nil
        }

        var children = TopChildrenAccumulator(keepTop: keepTopPerFolder)
        while let childURL = nextImmediateChild(from: enumerator) {
            if Task.isCancelled { break }
            if let node = await build(url: childURL, depth: depth + 1) {
                children.add(node)
            }
        }

        return DiskNode(
            url: url, kind: .folder, sizeBytes: children.totalSize,
            modifiedAt: directoryValues?.contentModificationDate,
            children: children.finalize(parentURL: url)
        )
    }

    private func summarizeChildren(of url: URL) async -> UInt64 {
        guard let enumerator = immediateChildren(of: url) else {
            await reporter.didSkip(url, reason: "Directory is not readable")
            return 0
        }

        var total: UInt64 = 0
        while let childURL = nextImmediateChild(from: enumerator) {
            if Task.isCancelled { break }
            total += await summarize(url: childURL)
        }
        return total
    }

    private func summarize(url: URL) async -> UInt64 {
        if Task.isCancelled { return 0 }
        if isSymbolicLink(url) {
            await reporter.didSkip(url, reason: "Symbolic link skipped")
            return 0
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            await reporter.didSkip(url, reason: "Path does not exist")
            return 0
        }

        if isDirectory.boolValue {
            await reporter.didScan(url.path)
            return await summarizeChildren(of: url)
        }

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            await reporter.didSkip(url, reason: "File metadata is not readable")
            return 0
        }
        if values.isSymbolicLink == true {
            await reporter.didSkip(url, reason: "Symbolic link skipped")
            return 0
        }
        guard values.isRegularFile == true else {
            await reporter.didSkip(url, reason: "Unsupported file type")
            return 0
        }
        await reporter.didScan(url.path)
        return UInt64(values.fileSize ?? 0)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func immediateChildren(of url: URL) -> FileManager.DirectoryEnumerator? {
        fileManager.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys), options: [])
    }

    private func nextImmediateChild(from enumerator: FileManager.DirectoryEnumerator) -> URL? {
        guard let url = enumerator.nextObject() as? URL else { return nil }
        enumerator.skipDescendants()
        return url
    }

    private var resourceKeys: Set<URLResourceKey> {
        [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
    }
}

/// Streaming top-K 聚合器:掃描期間只保留 keepTop 個最大節點與長尾總和。
private struct TopChildrenAccumulator {
    let keepTop: Int
    private(set) var totalSize: UInt64 = 0
    private var kept: [DiskNode] = []
    private var tailSize: UInt64 = 0
    private var tailCount = 0

    init(keepTop: Int) {
        self.keepTop = max(1, keepTop)
    }

    mutating func add(_ node: DiskNode) {
        totalSize += node.sizeBytes

        if kept.count < keepTop {
            insertKept(node)
            return
        }

        guard let smallestKept = kept.last, ranksBefore(node, smallestKept) else {
            addToTail(node)
            return
        }

        addToTail(kept.removeLast())
        insertKept(node)
    }

    func finalize(parentURL: URL) -> [DiskNode] {
        guard tailCount > 0 else { return kept }
        let aggregate = DiskNode(
            url: parentURL.appendingPathComponent("·other·"),
            name: "其他 \(tailCount) 個項目",
            kind: .file,                 // 不可下鑽
            sizeBytes: tailSize,
            modifiedAt: nil,
            isAggregate: true,
            aggregateCount: tailCount
        )
        return kept + [aggregate]
    }

    private mutating func insertKept(_ node: DiskNode) {
        kept.append(node)
        kept.sort(by: ranksBefore)
    }

    private mutating func addToTail(_ node: DiskNode) {
        tailSize += node.sizeBytes
        tailCount += 1
    }

    private func ranksBefore(_ lhs: DiskNode, _ rhs: DiskNode) -> Bool {
        lhs.sizeBytes == rhs.sizeBytes ? lhs.url.path < rhs.url.path : lhs.sizeBytes > rhs.sizeBytes
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
