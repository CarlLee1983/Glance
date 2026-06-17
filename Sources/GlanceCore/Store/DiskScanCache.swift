import Foundation

public struct DiskScanCacheEntry: Codable, Equatable, Sendable {
    public let rootPath: String
    public let scannedAt: Date
    public let root: DiskNode

    public init(rootPath: String, scannedAt: Date, root: DiskNode) {
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.root = root
    }
}

/// 把整棵 DiskNode 以 JSON 序列化到 Application Support，key = 正規化後 root 路徑的穩定雜湊。
public final class DiskScanCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    public func save(root: DiskNode, rootURL: URL, scannedAt: Date) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = DiskScanCacheEntry(
            rootPath: rootURL.standardizedFileURL.path, scannedAt: scannedAt, root: root
        )
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: rootURL), options: .atomic)
    }

    public func load(rootURL: URL) -> DiskScanCacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: rootURL)) else { return nil }
        return try? JSONDecoder().decode(DiskScanCacheEntry.self, from: data)
    }

    public func clear(rootURL: URL) {
        try? fileManager.removeItem(at: fileURL(for: rootURL))
    }

    private func fileURL(for rootURL: URL) -> URL {
        let key = rootURL.standardizedFileURL.path
        return directory.appendingPathComponent("scan-\(Self.stableHash(key)).json")
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
