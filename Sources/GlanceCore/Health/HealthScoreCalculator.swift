/// 用既有 SystemSnapshot 算系統健康分數。純函式、無副作用。
/// 演算法沿用 tw93/mole metrics_health.go,略過磁碟 I/O 與開機時長(Glance 未取樣)。
public enum HealthScoreCalculator {

    // 權重
    private static let cpuWeight = 30.0
    private static let memWeight = 25.0
    private static let diskWeight = 20.0
    private static let thermalWeight = 15.0

    // 門檻
    private static let cpuNormal = 50.0,  cpuHigh = 85.0
    private static let memNormal = 70.0,  memHigh = 88.0
    private static let diskWarn = 80.0,   diskCrit = 93.0
    private static let thermalNormal = 65.0, thermalHigh = 85.0

    public static func evaluate(_ snapshot: SystemSnapshot) -> HealthScore {
        var score = 100.0

        if let cpu = snapshot.cpu {
            score -= cpuPenalty(cpu.totalUsage * 100)
        }

        if let mem = snapshot.memory {
            score -= memPenalty(mem.usedFraction * 100)
            switch mem.pressure {
            case .warning: score -= 5
            case .critical: score -= 15
            case .normal: break
            }
        }

        if let disk = snapshot.disk {
            score -= diskPenalty(disk.usedFraction * 100)
        }

        if let temp = snapshot.sensors?.cpuTemperature, temp > 0 {
            score -= thermalPenalty(temp)
        }

        if let battery = snapshot.battery, battery.isPresent {
            score -= batteryPenalty(cycles: battery.cycleCount, health: battery.healthFraction)
        }

        let clamped = Int(max(0, min(100, score)).rounded())
        return HealthScore(value: clamped)
    }

    // mole CPU:超過 high 用全權重 * (u-normal)/high;否則半權重線性內插。
    private static func cpuPenalty(_ u: Double) -> Double {
        guard u > cpuNormal else { return 0 }
        if u > cpuHigh { return cpuWeight * (u - cpuNormal) / cpuHigh }
        return (cpuWeight / 2) * (u - cpuNormal) / (cpuHigh - cpuNormal)
    }

    // mole Memory:超過 high 用全權重 * (u-normal)/normal;否則半權重線性內插。
    private static func memPenalty(_ u: Double) -> Double {
        guard u > memNormal else { return 0 }
        if u > memHigh { return memWeight * (u - memNormal) / memNormal }
        return (memWeight / 2) * (u - memNormal) / (memHigh - memNormal)
    }

    // mole Disk:超過 crit 用全權重 * (u-warn)/(100-warn);否則半權重線性內插。
    private static func diskPenalty(_ u: Double) -> Double {
        guard u > diskWarn else { return 0 }
        if u > diskCrit { return diskWeight * (u - diskWarn) / (100 - diskWarn) }
        return (diskWeight / 2) * (u - diskWarn) / (diskCrit - diskWarn)
    }

    // mole Thermal:超過 high 直接滿權重;否則線性內插至滿權重。
    private static func thermalPenalty(_ t: Double) -> Double {
        guard t > thermalNormal else { return 0 }
        if t > thermalHigh { return thermalWeight }
        return thermalWeight * (t - thermalNormal) / (thermalHigh - thermalNormal)
    }

    // mole Battery:循環>900 或健康度<60% → −5;循環>800 或健康度<80% → −2。
    private static func batteryPenalty(cycles: Int?, health: Double?) -> Double {
        let cap = health.map { $0 * 100 }
        let cycle = cycles ?? 0
        if cycle > 900 || (cap.map { $0 < 60 } ?? false) { return 5 }
        if cycle > 800 || (cap.map { $0 < 80 } ?? false) { return 2 }
        return 0
    }
}
