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
