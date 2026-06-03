public struct DiskStats: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
    }
}

public struct DiskSnapshot: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
    }
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public protocol DiskStatsSource {
    func read() -> DiskStats?
}
