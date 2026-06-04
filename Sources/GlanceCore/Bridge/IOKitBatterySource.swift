import Foundation
import IOKit
import IOKit.ps

/// 透過 IOPowerSources 讀基本電源資訊;再從 AppleSmartBattery registry 補進階欄位。
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
        let adv = readAdvanced()
        return BatteryStats(
            isPresent: true,
            chargeFraction: Double(current) / Double(max),
            isCharging: charging,
            cycleCount: adv.cycleCount,
            healthFraction: adv.healthFraction,
            temperature: adv.temperature,
            powerWatts: adv.powerWatts)
    }

    private struct Advanced {
        var cycleCount: Int?
        var healthFraction: Double?
        var temperature: Double?
        var powerWatts: Double?
    }

    /// 從 AppleSmartBattery IORegistry 節點讀進階屬性。讀不到回全 nil。
    private func readAdvanced() -> Advanced {
        var adv = Advanced()
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return adv }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int? {
            guard let ref = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            else { return nil }
            return (ref as? NSNumber)?.intValue
        }

        adv.cycleCount = intProp("CycleCount")

        // 健康度 = 名義容量 / 設計容量。
        // NominalChargeCapacity 是電池管理修正後的容量(較準確),
        // 退而求其次用 AppleRawMaxCapacity。
        if let design = intProp("DesignCapacity"), design > 0,
           let maxCap = intProp("NominalChargeCapacity") ?? intProp("AppleRawMaxCapacity") {
            adv.healthFraction = Double(maxCap) / Double(design)
        }

        // 溫度單位為 1/100 °C。
        if let t = intProp("Temperature") {
            adv.temperature = Double(t) / 100.0
        }

        // 瞬時功率 = 電壓(mV) × 電流(mA) / 1e6 → W;電流放電為負。
        if let voltage = intProp("Voltage"),
           let amperage = intProp("InstantAmperage") ?? intProp("Amperage") {
            adv.powerWatts = Double(voltage) * Double(amperage) / 1_000_000.0
        }

        return adv
    }
}
