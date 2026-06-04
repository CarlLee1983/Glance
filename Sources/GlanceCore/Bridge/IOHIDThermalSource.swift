import Foundation
import IOKit

private typealias IOHIDEventSystemClientRef = CFTypeRef
private typealias IOHIDServiceClientRef = CFTypeRef
private typealias IOHIDEventRef = CFTypeRef

// Create/Copy 語意的私有符號回傳 +1 物件,須以 Unmanaged + takeRetainedValue() 接手
// 釋放擁有權,否則每次 read()(2–5 秒計時器呼叫)都會洩漏 client/services/字串/event。
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<IOHIDEventSystemClientRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64,
                                         _ options: Int32, _ timeout: Int64) -> Unmanaged<IOHIDEventRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private let kIOHIDEventTypeTemperature: Int64 = 15
// 事件欄位編碼為 (eventType << 16) | fieldIndex;此處為溫度事件(type 15)的 field 0。
private let kIOHIDEventFieldTemperature: Int32 = Int32(15 << 16)

/// 透過 **私有** IOHIDEventSystemClient API 讀溫度感測器。
///
/// - Important: `@_silgen_name` 綁定私有符號,無 App Store 合規保證,
///   也不受 Apple SDK 穩定性承諾約束;macOS 主版本升級後需重新驗證。
public struct IOHIDThermalSource: ThermalSource {
    public init() {}

    public func read() -> ThermalReading? {
        let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005]
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [IOHIDServiceClientRef] else {
            return nil
        }

        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        for service in services {
            guard let nameRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue(),
                  let name = nameRef as? String else { continue }
            guard let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() else { continue }
            let value = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperature)
            // 異常讀數過濾:0 以下與 150°C 以上視為無效(M-series throttle 約 ~105°C)。
            guard value > 0, value < 150 else { continue }
            switch Self.classify(name) {
            case .gpu: gpuTemps.append(value)
            case .cpu: cpuTemps.append(value)
            case .ignore: continue
            }
        }

        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let reading = ThermalReading(cpu: avg(cpuTemps), gpu: avg(gpuTemps))
        return (reading.cpu == nil && reading.gpu == nil) ? nil : reading
    }

    private enum Bucket { case cpu, gpu, ignore }

    /// 依感測器名稱歸類。Apple Silicon CPU/GPU 共晶片,實際暴露的多為
    /// `PMU tdie*`(`tdie` = 矽晶 die 溫度,作為 SoC 代理,歸 CPU);
    /// 板級 `tdev*`、校正 `tcal`、`gas gauge battery`、`NAND` 等非 die 感測器排除,
    /// 以免拉低或污染均值。
    ///
    /// Apple Silicon CPU+GPU 共用 die、無獨立 GPU 感測器名,故 GPU 恆 nil 為預期;
    /// `cpu`/`soc`/`pmgr` 為其他硬體(Intel 等)的後備關鍵字。
    private static func classify(_ name: String) -> Bucket {
        let lower = name.lowercased()
        if lower.contains("gpu") { return .gpu }
        if lower.contains("cpu") || lower.contains("soc") || lower.contains("pmgr") {
            return .cpu
        }
        // Apple Silicon:die 溫度感測器作為 CPU/SoC 溫度代表。
        if lower.contains("tdie") { return .cpu }
        return .ignore
    }
}
