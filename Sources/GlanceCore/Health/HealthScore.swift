/// 系統健康分數結果:0...100 分與對應分段。
public struct HealthScore: Equatable {
    public let value: Int          // 0...100
    public let band: HealthBand

    public init(value: Int, band: HealthBand) {
        self.value = value
        self.band = band
    }
}

/// 分數分段(門檻沿用 mole)。label 為中文顯示字串;顏色對應在 GlanceApp 端。
public enum HealthBand: Equatable {
    case excellent      // >= 85
    case good           // 65...84
    case fair           // 45...64
    case needsAttention // < 45

    public var label: String {
        switch self {
        case .excellent: return "系統健康"
        case .good: return "良好"
        case .fair: return "普通"
        case .needsAttention: return "注意"
        }
    }

    public static func from(score: Int) -> HealthBand {
        if score >= 85 { return .excellent }
        if score >= 65 { return .good }
        if score >= 45 { return .fair }
        return .needsAttention
    }
}
