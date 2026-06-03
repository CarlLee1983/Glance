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

    /// 一次列舉,同時回傳 CPU 與記憶體排行,避免重複 read()。
    public func sample() -> (topCPU: [ProcessUsage], topMemory: [ProcessUsage]) {
        guard let raws = source.read() else { return ([], []) }
        let t = clock()
        let cpuByPid = Dictionary(uniqueKeysWithValues: raws.map { ($0.pid, $0.cpuTimeSeconds) })
        let prev = previous
        let dt = prev.map { t - $0.time } ?? 0
        previous = (cpuByPid, t)

        let usages: [ProcessUsage] = raws.map { p in
            let fraction: Double
            if let prev, dt > 0, let prevCPU = prev.byPid[p.pid] {
                fraction = max(0, (p.cpuTimeSeconds - prevCPU) / dt)
            } else {
                fraction = 0
            }
            return ProcessUsage(pid: p.pid, name: p.name, cpuFraction: fraction, memoryBytes: p.memoryBytes)
        }
        let topCPU = Array(usages.sorted { $0.cpuFraction > $1.cpuFraction }.prefix(limit))
        let topMemory = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (topCPU, topMemory)
    }

    public func sampleTopByCPU() -> [ProcessUsage] { sample().topCPU }

    public func sampleTopByMemory() -> [ProcessUsage] { sample().topMemory }
}
