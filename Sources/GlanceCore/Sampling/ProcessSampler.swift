import Foundation

/// 以兩次取樣間各 pid 的 cpu 時間差 ÷ 牆鐘時間差,計算每個程式 CPU 佔比。
public final class ProcessSampler {
    private let source: RawProcessSource
    private let clock: () -> TimeInterval
    private let limit: Int
    private var previous: (byPid: [Int32: Double], time: TimeInterval)?

    public init(source: RawProcessSource,
                clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
                limit: Int = 5) {
        self.source = source
        self.clock = clock
        self.limit = limit
    }

    public func sampleTopByCPU() -> [ProcessUsage] {
        guard let raws = source.read() else { return [] }
        let t = clock()
        let cpuByPid = Dictionary(uniqueKeysWithValues: raws.map { ($0.pid, $0.cpuTimeSeconds) })
        defer { previous = (cpuByPid, t) }

        let prev = previous
        let dt = prev.map { t - $0.time } ?? 0

        let usages: [ProcessUsage] = raws.map { p in
            let fraction: Double
            if let prev, dt > 0, let prevCPU = prev.byPid[p.pid] {
                fraction = max(0, (p.cpuTimeSeconds - prevCPU) / dt)
            } else {
                fraction = 0
            }
            return ProcessUsage(pid: p.pid, name: p.name, cpuFraction: fraction, memoryBytes: p.memoryBytes)
        }
        return Array(usages.sorted { $0.cpuFraction > $1.cpuFraction }.prefix(limit))
    }

    public func sampleTopByMemory() -> [ProcessUsage] {
        guard let raws = source.read() else { return [] }
        let usages = raws.map {
            ProcessUsage(pid: $0.pid, name: $0.name, cpuFraction: 0, memoryBytes: $0.memoryBytes)
        }
        return Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }
}
