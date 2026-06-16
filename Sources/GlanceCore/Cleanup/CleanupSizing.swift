import Foundation

/// scanner / executor 共用的遞迴大小計算與符號連結判斷。internal,僅供模組內使用。
enum CleanupSizing {
    static func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// 遞迴計算 url 佔用位元組;符號連結回 0(不跟隨);不可讀目錄回 0。
    static func size(of url: URL, fileManager: FileManager) -> UInt64 {
        if isSymbolicLink(url, fileManager: fileManager) { return 0 }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(values?.fileSize ?? 0)
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        ) else { return 0 }

        var total: UInt64 = 0
        for child in children {
            total += size(of: child, fileManager: fileManager)
        }
        return total
    }
}
