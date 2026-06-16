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
