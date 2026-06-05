import Foundation

/// 把行程執行檔路徑歸類到所屬 app。純字串運算,不碰檔案系統,易於單元測試。
public enum AppGrouping {
    public struct AppIdentity: Equatable {
        public let groupKey: String
        public let appName: String
        public let bundleURL: URL?
        public init(groupKey: String, appName: String, bundleURL: URL?) {
            self.groupKey = groupKey
            self.appName = appName
            self.bundleURL = bundleURL
        }
    }

    /// 從執行檔路徑找出最後一個 `.app` 包;找不到(或路徑為空/nil)則用 fallbackName。
    public static func identity(executablePath: String?, fallbackName: String) -> AppIdentity {
        guard let path = executablePath, !path.isEmpty else {
            return AppIdentity(groupKey: fallbackName, appName: fallbackName, bundleURL: nil)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
            return AppIdentity(groupKey: fallbackName, appName: fallbackName, bundleURL: nil)
        }
        let appComponent = components[appIndex]
        let appName = String(appComponent.dropLast(".app".count))
        let bundlePath = "/" + components[0...appIndex].joined(separator: "/")
        return AppIdentity(
            groupKey: bundlePath,
            appName: appName.isEmpty ? fallbackName : appName,
            bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true))
    }
}
