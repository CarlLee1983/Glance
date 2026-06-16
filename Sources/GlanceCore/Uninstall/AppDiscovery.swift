import Foundation

/// async 列舉 apps 目錄直下的 `.app`,讀 Info.plist 取 bundleID/name,算大小。
/// 無 bundleID 者排除;依 bundleID 去重;依名稱排序。
public final class AppDiscovery: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func discover(
        appsDirectories: [URL] = UninstallLocations.appsDirectories()
    ) async -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()

        for dir in appsDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                if Task.isCancelled { return apps }
                if CleanupSizing.isSymbolicLink(entry, fileManager: fileManager) { continue }
                guard let info = Self.readInfo(entry, fileManager: fileManager),
                      let bundleID = info.bundleID, !bundleID.isEmpty,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let size = CleanupSizing.size(of: entry, fileManager: fileManager)
                let name = info.name ?? entry.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    bundleID: bundleID, name: name, bundleURL: entry, sizeBytes: size
                ))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func readInfo(
        _ appURL: URL, fileManager: FileManager
    ) -> (bundleID: String?, name: String?)? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else { return nil }
        let bundleID = plist["CFBundleIdentifier"] as? String
        let name = (plist["CFBundleName"] as? String) ?? (plist["CFBundleDisplayName"] as? String)
        return (bundleID, name)
    }
}
