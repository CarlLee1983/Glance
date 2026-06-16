import Foundation

/// 以兩次累計位元組差值 ÷ 經過時間計算讀/寫速率。clock 可注入以便測試。
public final class DiskIOSampler {
    private let source: DiskIOStatsSource
    private let clock: () -> TimeInterval
    private var previous: (counters: DiskIOCounters, time: TimeInterval)?

    public init(source: DiskIOStatsSource, clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.source = source
        self.clock = clock
    }

    public func sample() -> DiskIOSnapshot? {
        guard let now = source.read() else { return nil }
        let t = clock()
        defer { previous = (now, t) }
        guard let prev = previous else {
            return DiskIOSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0)
        }
        let dt = t - prev.time
        guard dt > 0 else {
            return DiskIOSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0)
        }
        let read = Double(now.readBytes &- prev.counters.readBytes) / dt
        let write = Double(now.writeBytes &- prev.counters.writeBytes) / dt
        return DiskIOSnapshot(readBytesPerSec: read, writeBytesPerSec: write)
    }
}
