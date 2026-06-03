/// CPU 原始累計 ticks(host_statistics HOST_CPU_LOAD_INFO 對應欄位)。
public struct CPUTicks: Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// 一次取樣的 CPU 使用情形,百分比為 0...1 分數。
public struct CPUSnapshot: Equatable {
    public let totalUsage: Double  // user+system+nice 佔比
    public let user: Double        // 含 nice
    public let system: Double
    public let idle: Double
    public init(totalUsage: Double, user: Double, system: Double, idle: Double) {
        self.totalUsage = totalUsage; self.user = user; self.system = system; self.idle = idle
    }

    public static let zero = CPUSnapshot(totalUsage: 0, user: 0, system: 0, idle: 1)
}

/// 提供 CPU 原始 ticks 的來源(可注入測試替身)。
public protocol CPUTicksSource {
    func read() -> CPUTicks?
}
