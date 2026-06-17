import Foundation

public enum DiskSpaceItemKind: Equatable, Sendable, Codable {
    case file
    case folder
}

public struct DiskSpaceItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let name: String
    public let sizeBytes: UInt64
    public let kind: DiskSpaceItemKind
    public let modifiedAt: Date?

    public init(url: URL, sizeBytes: UInt64, kind: DiskSpaceItemKind, modifiedAt: Date?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.modifiedAt = modifiedAt
    }
}

public struct DiskSpaceSkippedPath: Equatable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.id = url.path
        self.url = url
        self.reason = reason
    }
}

public enum DiskSpaceScanState: Equatable, Sendable {
    case running
    case completed
    case cancelled
}

public struct DiskSpaceScanProgress: Equatable, Sendable {
    public let scannedCount: Int
    public let skippedCount: Int
    public let currentPath: String?
    public let largestFolders: [DiskSpaceItem]
    public let largestFiles: [DiskSpaceItem]

    public init(
        scannedCount: Int,
        skippedCount: Int,
        currentPath: String?,
        largestFolders: [DiskSpaceItem],
        largestFiles: [DiskSpaceItem]
    ) {
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.currentPath = currentPath
        self.largestFolders = largestFolders
        self.largestFiles = largestFiles
    }
}

public struct DiskSpaceScanResult: Equatable, Sendable {
    public let rootURL: URL
    public let state: DiskSpaceScanState
    public let scannedCount: Int
    public let largestFolders: [DiskSpaceItem]
    public let largestFiles: [DiskSpaceItem]
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(
        rootURL: URL,
        state: DiskSpaceScanState,
        scannedCount: Int,
        largestFolders: [DiskSpaceItem],
        largestFiles: [DiskSpaceItem],
        skippedPaths: [DiskSpaceSkippedPath]
    ) {
        self.rootURL = rootURL
        self.state = state
        self.scannedCount = scannedCount
        self.largestFolders = largestFolders
        self.largestFiles = largestFiles
        self.skippedPaths = skippedPaths
    }
}
