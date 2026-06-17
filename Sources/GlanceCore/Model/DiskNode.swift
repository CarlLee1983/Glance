import Foundation

/// 磁碟掃描的樹節點。value type、遞迴結構,天然 Sendable + Codable(供快取)。
/// `isAggregate == true` 表示「其他 N 個項目」合成節點:只記總和與計數,不可下鑽、不可選取。
public struct DiskNode: Identifiable, Equatable, Sendable, Codable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: DiskSpaceItemKind
    public let sizeBytes: UInt64
    public let modifiedAt: Date?
    public let children: [DiskNode]
    public let isAggregate: Bool
    public let aggregateCount: Int

    public init(
        url: URL,
        name: String? = nil,
        kind: DiskSpaceItemKind,
        sizeBytes: UInt64,
        modifiedAt: Date?,
        children: [DiskNode] = [],
        isAggregate: Bool = false,
        aggregateCount: Int = 0
    ) {
        self.url = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.children = children
        self.isAggregate = isAggregate
        self.aggregateCount = aggregateCount
    }

    /// 可下鑽:資料夾且非合成節點且有子項。
    public var isDrillable: Bool { kind == .folder && !isAggregate && !children.isEmpty }
}

public struct DiskTreeScanProgress: Equatable, Sendable {
    public let scannedCount: Int
    public let skippedCount: Int
    public let currentPath: String?

    public init(scannedCount: Int, skippedCount: Int, currentPath: String?) {
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.currentPath = currentPath
    }
}

public struct DiskTreeScanResult: Equatable, Sendable {
    public let rootURL: URL
    public let state: DiskSpaceScanState
    public let scannedCount: Int
    public let root: DiskNode?          // root 不可讀時為 nil
    public let skippedPaths: [DiskSpaceSkippedPath]

    public init(
        rootURL: URL,
        state: DiskSpaceScanState,
        scannedCount: Int,
        root: DiskNode?,
        skippedPaths: [DiskSpaceSkippedPath]
    ) {
        self.rootURL = rootURL
        self.state = state
        self.scannedCount = scannedCount
        self.root = root
        self.skippedPaths = skippedPaths
    }
}
