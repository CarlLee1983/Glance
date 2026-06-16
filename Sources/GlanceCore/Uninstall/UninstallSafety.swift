import Foundation

/// 移到垃圾桶前的寫死護欄。`.app` 與關聯檔都必須是某白名單目錄的「直接子項」,
/// 經正規化後以該目錄為嚴格前綴(且不等於目錄本身),拒絕符號連結與過淺根。
public enum UninstallSafety {
    /// `.app` 必須是某 apps 目錄的直接子項、副檔名為 `.app`、非符號連結。
    public static func isDeletableApp(
        _ url: URL,
        within appsDirs: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        guard url.standardizedFileURL.pathExtension == "app" else { return false }
        return isDirectChild(url, of: appsDirs, fileManager: fileManager)
    }

    /// 關聯檔必須是某支援目錄的直接子項、非符號連結。
    public static func isDeletableRelated(
        _ url: URL,
        within supportDirs: [URL],
        fileManager: FileManager = .default
    ) -> Bool {
        isDirectChild(url, of: supportDirs, fileManager: fileManager)
    }

    /// 共用:url 是否為某根目錄的「直接子項」(元件數正好多 1、前綴相符、非 symlink)。
    private static func isDirectChild(
        _ url: URL,
        of roots: [URL],
        fileManager: FileManager
    ) -> Bool {
        let standardized = url.standardizedFileURL

        // 拒絕符號連結本身(standardizedFileURL 不解析最後一段 symlink,故仍可偵測)。
        if (try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return false
        }

        let target = standardized.pathComponents
        for root in roots {
            let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            // 防呆:拒絕過淺的根(如 "/")。
            guard rootComponents.count > 1 else { continue }
            // 直接子項:元件數正好比 root 多 1,且前綴完全等於 root。
            if target.count == rootComponents.count + 1,
               Array(target.prefix(rootComponents.count)) == rootComponents {
                return true
            }
        }
        return false
    }
}
