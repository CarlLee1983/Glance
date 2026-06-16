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
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                ) else { continue }

                // 用呼叫端傳入的 root 重新拼出子項 URL,保留其路徑形式(避免
                // Foundation 把 /var → /private/var 等 symlink 前綴正規化掉),
                // 報告/比對更直覺;指向的實體檔案不變。
                let children = entries.map {
                    root.appendingPathComponent($0.lastPathComponent)
                }

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
