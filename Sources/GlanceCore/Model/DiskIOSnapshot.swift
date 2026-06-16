/// 全部實體磁碟自開機起的累計讀/寫位元組數。
public struct DiskIOCounters: Equatable {
    public let readBytes: UInt64
    public let writeBytes: UInt64
    public init(readBytes: UInt64, writeBytes: UInt64) {
        self.readBytes = readBytes; self.writeBytes = writeBytes
    }
}

public struct DiskIOSnapshot: Equatable {
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public init(readBytesPerSec: Double, writeBytesPerSec: Double) {
        self.readBytesPerSec = readBytesPerSec; self.writeBytesPerSec = writeBytesPerSec
    }
}

public protocol DiskIOStatsSource {
    func read() -> DiskIOCounters?
}
