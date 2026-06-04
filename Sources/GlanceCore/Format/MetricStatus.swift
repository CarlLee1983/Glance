/// Dropdown badges and menu bar status icons use these coarse bands to keep
/// metric state wording stable.
public enum MetricStatus: Equatable {
    case normal
    case elevated
    case critical
    case charging

    public var label: String {
        switch self {
        case .normal: return "正常"
        case .elevated: return "偏高"
        case .critical: return "注意"
        case .charging: return "充電中"
        }
    }

    public static func load(fraction: Double) -> MetricStatus {
        band(fraction: fraction, elevated: 0.75, critical: 0.9)
    }

    public static func capacity(fraction: Double) -> MetricStatus {
        band(fraction: fraction, elevated: 0.8, critical: 0.9)
    }

    public static func battery(chargeFraction: Double, isCharging: Bool) -> MetricStatus {
        if isCharging { return .charging }
        return chargeFraction < 0.2 ? .critical : .normal
    }

    private static func band(fraction: Double, elevated: Double, critical: Double) -> MetricStatus {
        if fraction >= critical { return .critical }
        if fraction >= elevated { return .elevated }
        return .normal
    }
}
