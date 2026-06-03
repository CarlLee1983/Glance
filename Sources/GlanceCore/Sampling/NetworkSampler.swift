import Foundation

/// 以兩次累計位元組差值 ÷ 經過時間計算上/下載速率。clock 可注入以便測試。
public final class NetworkSampler {
    private let source: NetworkCountersSource
    private let clock: () -> TimeInterval
    private var previous: (counters: NetworkCounters, time: TimeInterval)?

    public init(source: NetworkCountersSource, clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.source = source
        self.clock = clock
    }

    public func sample() -> NetworkSnapshot? {
        guard let now = source.read() else { return nil }
        let t = clock()
        defer { previous = (now, t) }
        guard let prev = previous else {
            return NetworkSnapshot(downBytesPerSec: 0, upBytesPerSec: 0,
                                   totalDownBytes: now.received, totalUpBytes: now.sent)
        }
        let dt = t - prev.time
        guard dt > 0 else {
            return NetworkSnapshot(downBytesPerSec: 0, upBytesPerSec: 0,
                                   totalDownBytes: now.received, totalUpBytes: now.sent)
        }
        let down = Double(now.received &- prev.counters.received) / dt
        let up = Double(now.sent &- prev.counters.sent) / dt
        return NetworkSnapshot(downBytesPerSec: down, upBytesPerSec: up,
                               totalDownBytes: now.received, totalUpBytes: now.sent)
    }
}
