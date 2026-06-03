import Foundation
import IOKit.ps

/// 透過 IOPowerSources 讀取第一個電源資訊;無電池時回 isPresent = false。
public struct IOKitBatterySource: BatteryStatsSource {
    public init() {}

    public func read() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        }
        guard let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
        else {
            return BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        }
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        return BatteryStats(
            isPresent: true,
            chargeFraction: Double(current) / Double(max),
            isCharging: charging)
    }
}
