/// 介面累計位元組數(自開機起)。
public struct NetworkCounters: Equatable {
    public let received: UInt64
    public let sent: UInt64
    public init(received: UInt64, sent: UInt64) {
        self.received = received; self.sent = sent
    }
}

public struct NetworkSnapshot: Equatable {
    public let downBytesPerSec: Double
    public let upBytesPerSec: Double
    public let totalDownBytes: UInt64
    public let totalUpBytes: UInt64
    public init(downBytesPerSec: Double, upBytesPerSec: Double, totalDownBytes: UInt64, totalUpBytes: UInt64) {
        self.downBytesPerSec = downBytesPerSec; self.upBytesPerSec = upBytesPerSec
        self.totalDownBytes = totalDownBytes; self.totalUpBytes = totalUpBytes
    }
}

public protocol NetworkCountersSource {
    func read() -> NetworkCounters?
}
