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

    /// 記憶體按「身分」彙總,而非按 pid:同一 .app 包的行程加總,同一執行檔路徑的非 app 行程
    /// 也加總(比照 app 規則,避免漏報如 node/claude 這類多行程消費者)。不同路徑不會被誤加總。
    /// 由大到小排序取前 limit。
    static func aggregateMemory(_ raws: [RawProcess], limit: Int) -> [AppMemoryUsage] {
        var byKey: [String: (
            name: String,
            url: URL?,
            bytes: UInt64,
            count: Int,
            kind: AppMemoryUsage.Kind,
            executablePath: String?,
            firstPID: Int32
        )] = [:]
        for p in raws {
            let id = AppGrouping.identity(executablePath: p.executablePath, fallbackName: p.name)
            let kind = Self.memoryUsageKind(executablePath: p.executablePath)
            let key = Self.groupKey(identity: id, executablePath: p.executablePath, pid: p.pid)
            if var entry = byKey[key] {
                entry.bytes += p.memoryBytes
                entry.count += 1
                byKey[key] = entry
            } else {
                byKey[key] = (id.appName, id.bundleURL, p.memoryBytes, 1, kind, p.executablePath, p.pid)
            }
        }
        let apps = byKey.map { key, v in
            AppMemoryUsage(
                id: key,
                appName: v.name,
                bundleURL: v.url,
                memoryBytes: v.bytes,
                processCount: v.count,
                kind: v.kind,
                executablePath: v.executablePath,
                // 只有落單的行程才有可指認的 pid;多行程群組交由 row 展開去查明細。
                soloPID: v.count == 1 ? v.firstPID : nil
            )
        }
        let sorted = apps.sorted {
            if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
            if $0.appName != $1.appName { return $0.appName < $1.appName }
            return $0.id < $1.id
        }
        return Array(sorted.prefix(limit))
    }

    /// 群組鍵:app 用 bundle 路徑,非 app 用執行檔路徑,兩者皆無(取不到路徑)才退回行程名。
    private static func groupKey(identity: AppGrouping.AppIdentity, executablePath: String?, pid: Int32) -> String {
        if identity.bundleURL != nil { return identity.groupKey }
        if let path = executablePath, !path.isEmpty { return path }
        return "name:\(identity.appName)"
    }

    /// 出身分類:純由路徑判定。巢狀 .app(路徑中 .app 出現多於一次)視為 App 子行程。
    private static func memoryUsageKind(executablePath: String?) -> AppMemoryUsage.Kind {
        guard let path = executablePath, !path.isEmpty else { return .unknown }

        let appComponents = path.split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0.hasSuffix(".app") }
        if appComponents.count >= 2 { return .appChild }
        if appComponents.count == 1 { return .app }

        if path.hasPrefix("/System/")
            || path.hasPrefix("/usr/sbin/")
            || path.hasPrefix("/usr/libexec/")
            || path.hasPrefix("/sbin/")
            || path.hasPrefix("/Library/Apple/") {
            return .systemService
        }

        return .userProcess
    }
}
