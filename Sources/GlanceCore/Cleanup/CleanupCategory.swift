import Foundation

public enum CleanupCategoryID: String, CaseIterable, Sendable {
    case trash
    case userCaches
    case devCaches
}

/// 一個清理類別:顯示名稱 + 白名單根目錄(已展開 ~)。
public struct CleanupCategory: Equatable, Sendable, Identifiable {
    public let id: CleanupCategoryID
    public let displayName: String
    public let roots: [URL]

    public init(id: CleanupCategoryID, displayName: String, roots: [URL]) {
        self.id = id
        self.displayName = displayName
        self.roots = roots
    }

    /// 內建三類與寫死路徑。根目錄互不重疊,避免重複計算。
    public static func defaults(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [CleanupCategory] {
        func sub(_ path: String) -> URL { home.appendingPathComponent(path) }
        return [
            CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [sub(".Trash")]),
            CleanupCategory(
                id: .userCaches,
                displayName: "使用者快取與日誌",
                roots: [sub("Library/Caches"), sub("Library/Logs")]
            ),
            CleanupCategory(
                id: .devCaches,
                displayName: "開發工具快取",
                roots: [
                    sub("Library/Developer/Xcode/DerivedData"),
                    sub(".npm"),
                    sub(".cache"),
                ]
            ),
        ]
    }
}
