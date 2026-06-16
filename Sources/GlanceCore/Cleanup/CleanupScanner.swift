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
