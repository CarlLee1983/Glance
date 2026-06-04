import Foundation
import IOKit

// Create/Copy 語意的私有符號回傳 +1 物件,須以 Unmanaged + takeRetainedValue() 接手
// 釋放擁有權,否則每次 read()(計時器週期呼叫)都會洩漏 channels/subscription/samples 字典。
@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: CFString?, _ subgroup: CFString?,
                                         _ a: UInt64, _ b: UInt64, _ c: UInt64) -> Unmanaged<CFMutableDictionary>?

@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeMutableRawPointer?, _ channels: CFMutableDictionary,
                                        _ subbed: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                                        _ flags: UInt64, _ b: UnsafeMutableRawPointer?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subscription: CFTypeRef, _ channels: CFMutableDictionary,
                                   _ a: UnsafeMutableRawPointer?) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ prev: CFDictionary, _ current: CFDictionary,
                                        _ a: UnsafeMutableRawPointer?) -> Unmanaged<CFDictionary>?

// Get 語意(CF Get Rule):回傳 +0 借用參照,**不可**釋放;故宣告為非 Unmanaged。
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ ch: CFDictionary) -> CFString?

@_silgen_name("IOReportChannelGetUnitLabel")
private func IOReportChannelGetUnitLabel(_ ch: CFDictionary) -> CFString?

@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ ch: CFDictionary, _ a: Int32) -> Int64

/// 取樣字典中通道陣列的鍵名。
private let kIOReportChannelsKey = "IOReportChannels"

/// 以 IOReport「Energy Model」群組讀 SoC 能量,兩次取樣間差值換算瞬時瓦數。
///
/// 能量通道為累積計數器:瞬時功率 = 能量差 / 時間差。本來源為**有狀態**——
/// 保留上一筆取樣,首次 `read()` 僅建立基準回 nil,之後才回傳瓦數。
///
/// - Important: `@_silgen_name` 綁定**私有**符號,無 App Store 合規保證,
///   也不受 Apple SDK 穩定性承諾約束;macOS 主版本升級後需重新驗證單位與通道名。
/// - Warning: 非執行緒安全。`read()` 必須由單一串行佇列呼叫;
///   目前由 MetricsStore 的 DispatchSourceTimer(單一序列觸發)保證,
///   請勿並發呼叫(包含在 timer 運作中於主執行緒呼叫 tick())。
public final class IOReportPowerSource: PowerSource {
    private let subscription: CFTypeRef?
    private let channels: CFMutableDictionary?
    private var lastSample: CFDictionary?
    // 單調時鐘:`DispatchTime.uptimeNanoseconds` 不受 NTP 校時/回撥影響,
    // 且系統睡眠時暫停——與能量計數器於睡眠時同樣不前進的特性一致。
    private var lastTick: UInt64?

    public init() {
        guard let chans = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
            self.channels = nil; self.subscription = nil; return
        }
        self.channels = chans
        var subbed: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, chans, &subbed, 0, nil)?.takeRetainedValue()
        // subbed 為 +1 回傳,須釋放擁有權避免洩漏(訂閱後不再使用)。
        subbed?.release()
        self.subscription = sub
    }

    public func read() -> PowerReading? {
        guard let subscription, let channels,
              let current = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue()
        else { return nil }
        let nowTick = DispatchTime.now().uptimeNanoseconds
        defer { lastSample = current; lastTick = nowTick }

        guard let prev = lastSample, let prevTick = lastTick, nowTick > prevTick,
              let delta = IOReportCreateSamplesDelta(prev, current, nil)?.takeRetainedValue()
        else { return nil }
        let dt = Double(nowTick - prevTick) / 1_000_000_000
        // 最小取樣間隔守門:太短的間隔(抖動)會放大誤差,直接略過。
        guard dt >= 0.1 else { return nil }

        guard let chList = (delta as NSDictionary)[kIOReportChannelsKey] as? [CFDictionary] else { return nil }

        // Energy Model 群組為階層式:cluster(ecpu/pcpu)、per-core(ecpu0…)、
        // detail(ecpudtlXX)、sram 等都是 `cpu energy` 子集。全部相加會嚴重重複計算,
        // 故僅取彼此互斥的「頂層」通道:`cpu energy`、`gpu energy` 為 CPU/GPU 總量,
        // 其餘為獨立 SoC 子系統(DRAM/記憶體控制器/ISP/ANE/顯示…)。
        var cpu: Double?, gpu: Double?, total = 0.0
        for ch in chList {
            guard let nameRef = IOReportChannelGetChannelName(ch) else { continue }
            let name = (nameRef as String).lowercased()
            guard let domain = Self.topLevelDomain(name) else { continue }
            guard let unitRef = IOReportChannelGetUnitLabel(ch) else { continue }
            let unit = (unitRef as String).trimmingCharacters(in: .whitespaces).lowercased()
            // 將通道能量值換算成焦耳;Energy Model 單位實測為 mJ / nJ。
            guard let joules = Self.joules(Double(IOReportSimpleGetIntegerValue(ch, 0)), unit: unit) else { continue }
            let watts = joules / dt
            total += watts
            switch domain {
            case .cpu: cpu = (cpu ?? 0) + watts
            case .gpu: gpu = (gpu ?? 0) + watts
            case .other: break
            }
        }
        // 上限守門:M-series TDP 遠低於 100 W,200 已寬鬆;超出視為瞬時異常,棄樣。
        guard total > 0, total < 200 else { return nil }
        return PowerReading(system: total, cpu: cpu, gpu: gpu)
    }

    private enum Domain { case cpu, gpu, other }

    /// 只認頂層、互斥的能量通道,排除階層子通道避免重複計算。
    /// 未在白名單者回 nil(略過)。M-series Energy Model 實測通道:
    /// `cpu energy`(CPU 總量)、`gpu energy`(GPU 總量)、`dram`、`amcc`、`dcs`
    /// (記憶體控制器/快取)、`isp`、`ave`(ANE)、`msr`、`disp`/`dispext`(顯示)、`soc_aon`。
    ///
    /// - Note: 未知/新增通道一律落入 default → nil,因此**不計入 `total`**,
    ///   結果為**寧可低估也不重複計算**的安靜 under-count(較 double-count 安全)。
    ///   新 SoC 上市時應重新列舉通道(見 read() 解析的 channel name)並更新此白名單。
    private static func topLevelDomain(_ name: String) -> Domain? {
        switch name {
        case "cpu energy": return .cpu
        case "gpu energy": return .gpu
        case "dram", "amcc", "dcs", "isp", "ave", "msr", "disp", "dispext", "soc_aon":
            return .other
        default: return nil
        }
    }

    /// 依 IOReport 回報的單位標籤把原始能量值換算為焦耳。
    /// 未知單位回 nil(略過該通道),避免以錯誤倍率污染總功耗。
    private static func joules(_ value: Double, unit: String) -> Double? {
        switch unit {
        case "mj": return value / 1_000.0
        case "uj", "µj": return value / 1_000_000.0
        case "nj": return value / 1_000_000_000.0
        case "j": return value
        default: return nil
        }
    }
}
