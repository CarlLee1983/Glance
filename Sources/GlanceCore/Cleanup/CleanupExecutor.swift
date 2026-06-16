import Foundation

/// 收使用者勾選的類別,刪除其根目錄底下的內容物。刪每個路徑前:
/// 跳過符號連結、再經 CleanupSafety 驗證;失敗/被擋的路徑進 skippedPaths 不中斷整批。
/// 永不刪根目錄本身(只列舉並刪除根的直接子項)。
///
/// 安全性不變式:
/// - 本類別無可變的儲存屬性(只有 let fileManager),run() 的累加狀態全為函式內區域變數,
///   故 @unchecked Sendable 安全;日後若新增可變儲存屬性務必重新檢視。
/// - reclaimedBytes 為「刪除前」以 CleanupSizing 估算之值(無法在刪除後量測),屬估計值。
/// - 已知並接受的 TOCTOU:isDeletable 檢查與 removeItem 之間存在極小競態窗口;本工具僅操作
///   使用者自身目錄,攻擊者需先具備該目錄寫入權方能利用,故視為可接受風險。removeItem 對
///   葉節點 symlink 只會移除連結本身、不跟隨。
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
                // 直接使用 contentsOfDirectory 回傳的正規 URL(可能為 /private/var 形式);
                // 切勿用 root 重拼子項,否則所有項目都會變成 root 的後代,
                // 使 CleanupSafety.isDeletable 永遠為真、第二層護欄失效。
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
