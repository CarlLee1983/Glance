import Foundation

/// 分析器的「移到垃圾桶」護欄。異於 UninstallSafety 的 depth-1:此處允許任意深度,
/// 但目標必須是掃描 root 的「嚴格子孫」、非 root/祖先、非 symlink 葉、且不在保護清單。
public enum DiskTrashSafety {
    /// 即使位於 root 之下仍硬擋整包刪除的關鍵頂層目錄(預設清單)。
    public static func defaultProtectedPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        ["Library", ".ssh", "Documents", "Desktop", "Pictures", "Movies", "Music"]
            .map { home.appendingPathComponent($0) }
    }

    public static func isDeletable(
        _ url: URL,
        withinRoot root: URL,
        protectedPaths: [URL] = defaultProtectedPaths(),
        fileManager: FileManager = .default
    ) -> Bool {
        // 1) 拒絕 symlink 葉(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        let standardized = url.standardizedFileURL
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        // 2) root 防呆:拒絕過淺的根(如 "/")。
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard rootComponents.count > 1 else { return false }

        // 3) 必須是 root 的嚴格子孫(元件數 > root 且前綴相符)。
        //    以「最深已存在祖先」解析符號連結(沿用 CleanupSafety),可擋中間目錄 symlink
        //    在目標尚未存在時造成的逃逸——本護欄允許任意深度,正是該防的情境。
        let targetComponents = CleanupSafety.resolvedComponents(of: standardized, fileManager: fileManager)
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            return false
        }

        // 4) 拒絕保護清單(精確比對整個目錄)。
        for protected in protectedPaths {
            if targetComponents == protected.standardizedFileURL.resolvingSymlinksInPath().pathComponents {
                return false
            }
        }

        return true
    }
}
