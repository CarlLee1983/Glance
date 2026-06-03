public struct BatteryStats: Equatable {
    public let isPresent: Bool
    public let chargeFraction: Double  // 0...1
    public let isCharging: Bool
    public init(isPresent: Bool, chargeFraction: Double, isCharging: Bool) {
        self.isPresent = isPresent; self.chargeFraction = chargeFraction; self.isCharging = isCharging
    }
}

public typealias BatterySnapshot = BatteryStats

public protocol BatteryStatsSource {
    func read() -> BatteryStats?
}
