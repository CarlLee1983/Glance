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
