import Foundation

public final class DiskSpaceAnalyzer: @unchecked Sendable {
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
        let state = ScanAccumulator(rootURL: rootURL, maxResults: maxResults)
        let scanner = ScanTraversal(fileManager: fileManager, progress: progress)
        _ = await scanner.scan(url: rootURL, state: state)
        return state.result(cancelled: Task.isCancelled)
    }
}

private struct ScanTraversal {
    let fileManager: FileManager
    let progress: DiskSpaceAnalyzer.ProgressHandler?

    func scan(url: URL, state: ScanAccumulator) async -> UInt64 {
        if Task.isCancelled { return 0 }

        guard !isSymbolicLink(url) else {
            await skip(url, reason: "Symbolic link skipped", state: state)
            return 0
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            await skip(url, reason: "Path does not exist", state: state)
            return 0
        }

        if isDirectory.boolValue {
            return await scanDirectory(url, state: state)
        }

        return await scanFile(url, state: state)
    }

    private func scanDirectory(_ url: URL, state: ScanAccumulator) async -> UInt64 {
        if Task.isCancelled { return 0 }

        let directoryValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else {
            await skip(url, reason: "Directory is not readable", state: state)
            return 0
        }

        state.scannedCount += 1
        await emitProgress(state, currentURL: url)

        var total: UInt64 = 0
        for child in children {
            if Task.isCancelled { break }
            let childURL = url.appendingPathComponent(child.lastPathComponent)
            total += await scan(url: childURL, state: state)
        }

        state.recordFolder(url: url, sizeBytes: total, modifiedAt: directoryValues?.contentModificationDate)
        await emitProgress(state, currentURL: url)
        return total
    }

    private func scanFile(_ url: URL, state: ScanAccumulator) async -> UInt64 {
        if Task.isCancelled { return 0 }

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            await skip(url, reason: "File metadata is not readable", state: state)
            return 0
        }

        if values.isSymbolicLink == true {
            await skip(url, reason: "Symbolic link skipped", state: state)
            return 0
        }

        guard values.isRegularFile == true else {
            await skip(url, reason: "Unsupported file type", state: state)
            return 0
        }

        let size = UInt64(values.fileSize ?? 0)
        state.scannedCount += 1
        state.recordFile(url: url, sizeBytes: size, modifiedAt: values.contentModificationDate)
        await emitProgress(state, currentURL: url)
        return size
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func skip(_ url: URL, reason: String, state: ScanAccumulator) async {
        state.skip(url, reason: reason)
        await emitProgress(state, currentURL: url)
    }

    private func emitProgress(_ state: ScanAccumulator, currentURL: URL) async {
        guard let progress else { return }
        await progress(state.progress(currentPath: currentURL.path))
    }

    private var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
    }
}

private final class ScanAccumulator {
    let rootURL: URL
    let maxResults: Int
    var scannedCount = 0
    var largestFolders: [DiskSpaceItem] = []
    var largestFiles: [DiskSpaceItem] = []
    var skippedPaths: [DiskSpaceSkippedPath] = []

    init(rootURL: URL, maxResults: Int) {
        self.rootURL = rootURL
        self.maxResults = maxResults
    }

    func recordFile(url: URL, sizeBytes: UInt64, modifiedAt: Date?) {
        largestFiles = inserting(DiskSpaceItem(url: url, sizeBytes: sizeBytes, kind: .file, modifiedAt: modifiedAt), into: largestFiles)
    }

    func recordFolder(url: URL, sizeBytes: UInt64, modifiedAt: Date?) {
        largestFolders = inserting(DiskSpaceItem(url: url, sizeBytes: sizeBytes, kind: .folder, modifiedAt: modifiedAt), into: largestFolders)
    }

    func skip(_ url: URL, reason: String) {
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

    private func inserting(_ item: DiskSpaceItem, into currentItems: [DiskSpaceItem]) -> [DiskSpaceItem] {
        var items = currentItems
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
        return items
    }
}
