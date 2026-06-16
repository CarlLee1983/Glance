import Foundation

/// 解除安裝器掃描/驗證用的寫死位置。
public enum UninstallLocations {
    /// 列舉使用者安裝 App 的目錄。
    public static func appsDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// 可能存放關聯檔的 ~/Library 子目錄。
    public static func supportDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "Library/Containers",
            "Library/Group Containers",
            "Library/Saved Application State",
            "Library/Logs",
            "Library/HTTPStorages",
            "Library/WebKit",
            "Library/Cookies",
            "Library/LaunchAgents",
        ].map { home.appendingPathComponent($0, isDirectory: true) }
    }
}
