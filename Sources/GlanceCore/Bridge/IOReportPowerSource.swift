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

// Get 語意(CF Get Rule):回傳 +0 借用參照。必須宣告為 Unmanaged 並以 takeUnretainedValue()
// 取值——裸 CFString? 會讓 Swift 套用 owned(+1)回傳慣例而在作用域結束多釋放一次,
// 造成 IOReport 內部字串被提早釋放(use-after-free,下次存取即崩潰)。
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ ch: CFDictionary) -> Unmanaged<CFString>?

@_silgen_name("IOReportChannelGetUnitLabel")
private func IOReportChannelGetUnitLabel(_ ch: CFDictionary) -> Unmanaged<CFString>?

@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ ch: CFDictionary, _ a: Int32) -> Int64

// 官方走訪 API:對取樣字典的每個 channel 同步呼叫 block,傳入有效的 IOReportChannelRef。
// 必須用此法,不可手動從取樣字典取出原始陣列元素當 channel(會 use-after-free 崩潰)。
@_silgen_name("IOReportIterate")
private func IOReportIterate(_ samples: CFDictionary,
                            _ block: @convention(block) (CFDictionary) -> Int32) -> Int32

/// 以 IOReport「Energy Model」群組讀 SoC 能量,換算瞬時瓦數。
///
/// 能量通道為累積計數器:瞬時功率 = 能量差 / 時間差。每次 `read()` 於單次呼叫內
/// 取兩筆全新取樣(中間隔 `sampleWindow`)算一次差值——**不可**把取樣留到下次當基準,
/// 因 `IOReportCreateSamplesDelta` 對輸入有破壞性,跨呼叫重用會導致第二次崩潰。
///
/// - Important: `@_silgen_name` 綁定**私有**符號,無 App Store 合規保證,
///   也不受 Apple SDK 穩定性承諾約束;macOS 主版本升級後需重新驗證單位與通道名。
/// - Warning: 共用單一 IOReport 訂閱,非執行緒安全;須由單一串行來源驅動
///   (MetricsStore 的 DispatchSourceTimer),請勿並發呼叫。
public final class IOReportPowerSource: PowerSource {
    private let subscription: CFTypeRef?
    private let channels: CFMutableDictionary?
    /// 單次 read() 內量測窗長度(秒)。能量累積差需一段間隔換算瞬時功率。
    private let sampleWindow: TimeInterval = 0.1

    public init() {
        guard let chans = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
            self.channels = nil; self.subscription = nil; return
        }
        self.channels = chans
        var subbed: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, chans, &subbed, 0, nil)?.takeRetainedValue()
        subbed?.release()  // +1 出參,訂閱後不再使用
        self.subscription = sub
    }

    public func read() -> PowerReading? {
        // 於單次呼叫內取兩筆全新 sample、量測窗後算一次 delta。
        // 不可把 sample 留到下次當 prev——IOReportCreateSamplesDelta 對輸入有破壞性,
        // 跨呼叫重用 sample 會導致第二次 delta 的通道參照損壞而崩潰。
        guard let subscription, let channels,
              let s1 = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue()
        else { return nil }
        let t1 = DispatchTime.now().uptimeNanoseconds
        Thread.sleep(forTimeInterval: sampleWindow)
        guard let s2 = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let t2 = DispatchTime.now().uptimeNanoseconds
        guard let delta = IOReportCreateSamplesDelta(s1, s2, nil)?.takeRetainedValue() else { return nil }
        let dt = Double(t2 - t1) / 1_000_000_000
        guard dt >= 0.05 else { return nil }

        // Energy Model 群組為階層式:cluster(ecpu/pcpu)、per-core(ecpu0…)、
        // detail(ecpudtlXX)、sram 等都是 `cpu energy` 子集。全部相加會嚴重重複計算,
        // 故僅取彼此互斥的「頂層」通道:`cpu energy`、`gpu energy` 為 CPU/GPU 總量,
        // 其餘為獨立 SoC 子系統(DRAM/記憶體控制器/ISP/ANE/顯示…)。
        // 以官方 IOReportIterate 走訪;block 為同步呼叫,可安全擷取本地變數。
        var cpu: Double?, gpu: Double?, total = 0.0
        let kIOReportIterOk: Int32 = 0
        _ = IOReportIterate(delta) { ch in
            guard let nameRef = IOReportChannelGetChannelName(ch)?.takeUnretainedValue() else { return kIOReportIterOk }
            let name = (nameRef as String).lowercased()
            guard let domain = Self.topLevelDomain(name) else { return kIOReportIterOk }
            guard let unitRef = IOReportChannelGetUnitLabel(ch)?.takeUnretainedValue() else { return kIOReportIterOk }
            let unit = (unitRef as String).trimmingCharacters(in: .whitespaces).lowercased()
            // 將通道能量值換算成焦耳;Energy Model 單位實測為 mJ / nJ。
            guard let joules = Self.joules(Double(IOReportSimpleGetIntegerValue(ch, 0)), unit: unit) else { return kIOReportIterOk }
            let watts = joules / dt
            total += watts
            switch domain {
            case .cpu: cpu = (cpu ?? 0) + watts
            case .gpu: gpu = (gpu ?? 0) + watts
            case .other: break
            }
            return kIOReportIterOk
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
