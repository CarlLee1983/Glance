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
        let standardized = url.standardizedFileURL

        // 拒絕符號連結本身(永不刪、永不跟隨;由呼叫端略過)。
        // standardizedFileURL 不解析最後一段 symlink,故仍可偵測。
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        // 解析路徑中所有符號連結後再比對,可擋「中間目錄為 symlink」的逃逸:
        // 例如 root/link/x(link → /outside)經解析後落在 root 之外即被拒絕。
        // 注意:Foundation 的 resolvingSymlinksInPath() 只會解析「磁碟上實際存在」
        // 的路徑段;若刪除目標尚未存在(常見:即將被刪的檔名),中間 symlink 不會被
        // 解析,逃逸仍會成立。故改以「最深的已存在祖先」解析後再接回不存在的尾段。
        let targetComponents = Self.resolvedComponents(of: standardized, fileManager: fileManager)

        for root in roots {
            let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            // 防呆:拒絕過淺的根(如 "/"),避免一個錯誤白名單授權整顆磁碟。
            guard rootComponents.count > 1 else { continue }
            // 必須是 root 的嚴格後代:元件數更多,且前綴完全等於 root。
            if targetComponents.count > rootComponents.count,
               Array(targetComponents.prefix(rootComponents.count)) == rootComponents {
                return true
            }
        }
        return false
    }

    /// 解析最深「已存在祖先」的符號連結,再接回尚未存在的尾段,回傳正規化後的路徑元件。
    /// 這能在刪除目標本身尚未存在時,仍揭露中間目錄 symlink 造成的真實落點。
    /// 同模組共用:`DiskTrashSafety` 亦以此擋中間 symlink 逃逸。
    static func resolvedComponents(
        of url: URL,
        fileManager: FileManager
    ) -> [String] {
        var tail: [String] = []
        var probe = url.standardizedFileURL
        // 逐層上溯到磁碟上實際存在的祖先;沿途把不存在的尾段暫存起來。
        while !fileManager.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            tail.insert(probe.lastPathComponent, at: 0)
            probe = probe.deletingLastPathComponent().standardizedFileURL
        }
        // 已存在的祖先解析掉所有 symlink,再接回原本不存在的尾段。
        return probe.resolvingSymlinksInPath().pathComponents + tail
    }
}
