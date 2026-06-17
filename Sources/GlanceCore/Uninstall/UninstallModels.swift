import Foundation

/// 一個使用者安裝的 App。
public struct InstalledApp: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let bundleURL: URL
    public let sizeBytes: UInt64

    public var id: String { bundleID }

    public init(bundleID: String, name: String, bundleURL: URL, sizeBytes: UInt64) {
        self.bundleID = bundleID
        self.name = name
        self.bundleURL = bundleURL
        self.sizeBytes = sizeBytes
    }
}

/// 一個與 App 關聯的散落檔/目錄。
public struct RelatedFile: Hashable, Equatable, Sendable, Identifiable {
    public let url: URL
    public let sizeBytes: UInt64

    public var id: String { url.path }

    public init(url: URL, sizeBytes: UInt64) {
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

/// 解除安裝計畫:App 本體 + 關聯檔。
public struct UninstallPlan: Equatable, Sendable {
    public let app: InstalledApp
    public let relatedFiles: [RelatedFile]

    public init(app: InstalledApp, relatedFiles: [RelatedFile]) {
        self.app = app
        self.relatedFiles = relatedFiles
    }

    /// 本體 + 全部關聯檔的合計大小。
    public var totalBytes: UInt64 {
        app.sizeBytes + relatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    /// 待處理項目數(本體 1 + 關聯數)。
    public var itemCount: Int { 1 + relatedFiles.count }
}

/// 解除安裝執行結果。
public struct UninstallRunResult: Equatable, Sendable {
    public let trashedCount: Int
    public let freedBytes: UInt64
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(trashedCount: Int, freedBytes: UInt64, skippedPaths: [DiskSpaceSkippedPath]) {
        self.trashedCount = trashedCount
        self.freedBytes = freedBytes
        self.skippedPaths = skippedPaths
    }

    public var skippedCount: Int { skippedPaths.count }
}

/// 執行進度回呼。
public struct UninstallProgress: Equatable, Sendable {
    public let currentPath: String?
    public let trashedCount: Int

    public init(currentPath: String?, trashedCount: Int) {
        self.currentPath = currentPath
        self.trashedCount = trashedCount
    }
}
