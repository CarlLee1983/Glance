import Darwin

/// 以 statfs("/") 取得根卷容量。
public struct StatfsDiskSource: DiskStatsSource {
    private let path: String
    public init(path: String = "/") { self.path = path }

    public func read() -> DiskStats? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let free = UInt64(fs.f_bavail) * blockSize
        let used = total >= free ? total - free : 0
        return DiskStats(totalBytes: total, usedBytes: used)
    }
}
