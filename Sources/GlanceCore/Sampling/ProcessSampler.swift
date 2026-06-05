import Foundation

/// 以兩次取樣間各 pid 的 cpu 時間差 ÷ 牆鐘時間差,計算每個程式 CPU 佔比;
/// 記憶體則按所屬 app 彙總(含 helper 子行程)。
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

    /// 一次列舉,同時回傳 CPU(單行程)與記憶體(按 app 彙總)排行,避免重複 read()。
    public func sample() -> (topCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
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
        let topMemoryApps = Self.aggregateMemory(raws, limit: limit)
        return (topCPU, topMemoryApps)
    }

    public func sampleTopByCPU() -> [ProcessUsage] { sample().topCPU }

    public func sampleTopMemoryApps() -> [AppMemoryUsage] { sample().topMemoryApps }

    /// 按 app 鍵把各行程記憶體加總,由大到小排序取前 limit。
    static func aggregateMemory(_ raws: [RawProcess], limit: Int) -> [AppMemoryUsage] {
        var byKey: [String: (name: String, url: URL?, bytes: UInt64, count: Int)] = [:]
        for p in raws {
            let id = AppGrouping.identity(executablePath: p.executablePath, fallbackName: p.name)
            if var entry = byKey[id.groupKey] {
                entry.bytes += p.memoryBytes
                entry.count += 1
                byKey[id.groupKey] = entry
            } else {
                byKey[id.groupKey] = (id.appName, id.bundleURL, p.memoryBytes, 1)
            }
        }
        let apps = byKey.map { key, v in
            AppMemoryUsage(id: key, appName: v.name, bundleURL: v.url, memoryBytes: v.bytes, processCount: v.count)
        }
        let sorted = apps.sorted {
            $0.memoryBytes == $1.memoryBytes ? $0.appName < $1.appName : $0.memoryBytes > $1.memoryBytes
        }
        return Array(sorted.prefix(limit))
    }
}
