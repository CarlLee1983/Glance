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
