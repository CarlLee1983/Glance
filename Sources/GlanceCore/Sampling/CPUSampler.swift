/// 以兩次 ticks 的差值計算 CPU 使用率。第一次取樣無前值 → 回傳 zero。
public final class CPUSampler {
    private let source: CPUTicksSource
    private var previous: CPUTicks?

    public init(source: CPUTicksSource) {
        self.source = source
    }

    public func sample() -> CPUSnapshot? {
        guard let now = source.read() else { return nil }
        defer { previous = now }
        guard let prev = previous else { return .zero }

        let dUser = Double(now.user &- prev.user)
        let dSystem = Double(now.system &- prev.system)
        let dIdle = Double(now.idle &- prev.idle)
        let dNice = Double(now.nice &- prev.nice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return .zero }

        let busy = dUser + dSystem + dNice
        return CPUSnapshot(
            totalUsage: busy / total,
            user: (dUser + dNice) / total,
            system: dSystem / total,
            idle: dIdle / total
        )
    }
}
