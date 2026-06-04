public struct BatteryStats: Equatable {
    public let isPresent: Bool
    public let chargeFraction: Double  // 0...1
    public let isCharging: Bool
    public let cycleCount: Int?        // 循環次數
    public let healthFraction: Double? // maxCapacity / designCapacity(0...1)
    public let temperature: Double?    // °C
    public let powerWatts: Double?     // 充/放電瓦數(放電為負)

    public init(isPresent: Bool, chargeFraction: Double, isCharging: Bool,
                cycleCount: Int? = nil, healthFraction: Double? = nil,
                temperature: Double? = nil, powerWatts: Double? = nil) {
        self.isPresent = isPresent; self.chargeFraction = chargeFraction
        self.isCharging = isCharging; self.cycleCount = cycleCount
        self.healthFraction = healthFraction; self.temperature = temperature
        self.powerWatts = powerWatts
    }
}

public typealias BatterySnapshot = BatteryStats

public protocol BatteryStatsSource {
    func read() -> BatteryStats?
}
