import Foundation

/// 以 bundleID 嚴格比對找關聯檔:檔名 == bundleID 或以 "bundleID." 開頭。
/// 跳過符號連結,並經 UninstallSafety 二次護欄(直接子項)。
public final class RelatedFileFinder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func find(
        bundleID: String,
        supportDirectories: [URL] = UninstallLocations.supportDirectories()
    ) async -> [RelatedFile] {
        guard !bundleID.isEmpty else { return [] }
        let dotPrefix = bundleID + "."
        var files: [RelatedFile] = []

        for dir in supportDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []
            ) else { continue }

            for entry in entries {
                if Task.isCancelled { return files }
                let name = entry.lastPathComponent
                guard name == bundleID || name.hasPrefix(dotPrefix) else { continue }
                if CleanupSizing.isSymbolicLink(entry, fileManager: fileManager) { continue }
                guard UninstallSafety.isDeletableRelated(
                    entry, within: supportDirectories, fileManager: fileManager
                ) else { continue }
                let size = CleanupSizing.size(of: entry, fileManager: fileManager)
                files.append(RelatedFile(url: entry, sizeBytes: size))
            }
        }

        return files
    }
}
