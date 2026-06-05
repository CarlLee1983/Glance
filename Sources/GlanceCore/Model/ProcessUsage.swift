/// libproc 取得的單一程式原始資料。cpuTimeSeconds 為累計使用者+系統 CPU 秒數。
public struct RawProcess: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuTimeSeconds: Double
    public let memoryBytes: UInt64
    public let executablePath: String?
    public init(pid: Int32, name: String, cpuTimeSeconds: Double, memoryBytes: UInt64, executablePath: String? = nil) {
        self.pid = pid; self.name = name
        self.cpuTimeSeconds = cpuTimeSeconds; self.memoryBytes = memoryBytes
        self.executablePath = executablePath
    }
}

/// 對外呈現的單一程式使用率。cpuFraction 可能 > 1(多核)。
public struct ProcessUsage: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuFraction: Double
    public let memoryBytes: UInt64
    public init(pid: Int32, name: String, cpuFraction: Double, memoryBytes: UInt64) {
        self.pid = pid; self.name = name
        self.cpuFraction = cpuFraction; self.memoryBytes = memoryBytes
    }
}

public protocol RawProcessSource {
    func read() -> [RawProcess]?
}
