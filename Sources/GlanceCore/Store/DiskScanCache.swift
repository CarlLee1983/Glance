import Foundation

public struct DiskScanCacheEntry: Codable, Equatable, Sendable {
    public let rootPath: String
    public let scannedAt: Date
    public let retainedDepth: Int
    public let root: DiskNode

    public init(rootPath: String, scannedAt: Date, retainedDepth: Int, root: DiskNode) {
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.retainedDepth = retainedDepth
        self.root = root
    }
}

/// 把保留深度內的 DiskNode 樹以 JSON 序列化到 Application Support。
/// 檔名含格式版本與 retainedDepth,避免載入舊版未裁剪的巨大快取。
public final class DiskScanCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let expectedRetainedDepth: Int

    public init(directory: URL? = nil, expectedRetainedDepth: Int = 2, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.expectedRetainedDepth = expectedRetainedDepth
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    public func save(root: DiskNode, rootURL: URL, scannedAt: Date) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = DiskScanCacheEntry(
            rootPath: rootURL.standardizedFileURL.path,
            scannedAt: scannedAt,
            retainedDepth: expectedRetainedDepth,
            root: root
        )
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: rootURL), options: .atomic)
    }

    public func load(rootURL: URL) -> DiskScanCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: rootURL)) else { return nil }
        guard let entry = try? JSONDecoder().decode(DiskScanCacheEntry.self, from: data),
              entry.retainedDepth == expectedRetainedDepth else {
            return nil
        }
        return entry
    }

    public func clear(rootURL: URL) {
        try? fileManager.removeItem(at: fileURL(for: rootURL))
    }

    func fileURLForTesting(rootURL: URL) -> URL { fileURL(for: rootURL) }

    func legacyFileURLForTesting(rootURL: URL) -> URL {
        let key = rootURL.standardizedFileURL.path
        return directory.appendingPathComponent("scan-\(Self.stableHash(key)).json")
    }

    private func fileURL(for rootURL: URL) -> URL {
        let key = rootURL.standardizedFileURL.path
        return directory.appendingPathComponent("scan-v2-d\(expectedRetainedDepth)-\(Self.stableHash(key)).json")
    }

    /// djb2：Hasher 每次執行 seed 不同，不可用於檔名；此函式跨執行穩定。
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Glance/DiskScanCache", isDirectory: true)
    }
}
