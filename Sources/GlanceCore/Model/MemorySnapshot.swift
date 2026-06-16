public enum MemoryPressure: String, Equatable {
    case normal, warning, critical
}

/// 記憶體原始統計(已換算為位元組)。
public struct MemoryStats: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MemoryPressure
    public init(totalBytes: UInt64, usedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
        self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
}

public struct MemorySnapshot: Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MemoryPressure
    public init(usedBytes: UInt64, totalBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes; self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public protocol MemoryStatsSource {
    func read() -> MemoryStats?
}

extension MemoryPressure {
    /// 由已用比例與 swap 推導記憶體壓力(取代不可靠的 kernel pressure level)。
    /// >90% 已用、或 swap 超過實體記憶體一半 → critical;>75% → warning;否則 normal。
    public static func evaluate(usedBytes: UInt64, totalBytes: UInt64, swapUsedBytes: UInt64) -> MemoryPressure {
        guard totalBytes > 0 else { return .normal }
        let usedFraction = Double(usedBytes) / Double(totalBytes)
        if usedFraction > 0.90 || swapUsedBytes > totalBytes / 2 { return .critical }
        if usedFraction > 0.75 { return .warning }
        return .normal
    }

    /// 歷史編碼與分段著色用序數:normal=0 / warning=1 / critical=2。
    public var level: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    /// 下拉副標顯示字串。
    public var displayLabel: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "嚴重"
        }
    }
}
