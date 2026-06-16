import Foundation

/// 永久刪除前的寫死護欄:只允許刪白名單根目錄「底下」的內容物。
/// 以正規化後的 pathComponents 做嚴格前綴比對,可擋 `../` 路徑遍歷與
/// 共享前綴(Caches vs Caches2)的誤判;符號連結一律拒絕。
public enum CleanupSafety {
    public static func isDeletable(
        _ url: URL,
        within roots: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        let target = url.standardizedFileURL

        // 拒絕符號連結(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        let targetComponents = target.pathComponents
        for root in roots {
            let rootComponents = root.standardizedFileURL.pathComponents
            // 必須是 root 的嚴格後代:元件數更多,且前綴完全等於 root。
            if targetComponents.count > rootComponents.count,
               Array(targetComponents.prefix(rootComponents.count)) == rootComponents {
                return true
            }
        }
        return false
    }
}
