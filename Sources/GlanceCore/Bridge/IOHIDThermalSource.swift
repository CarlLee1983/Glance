import Foundation
import IOKit

private typealias IOHIDEventSystemClientRef = CFTypeRef
private typealias IOHIDServiceClientRef = CFTypeRef
private typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64,
                                         _ options: Int32, _ timeout: Int64) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private let kIOHIDEventTypeTemperature: Int64 = 15
private let kIOHIDEventFieldTemperature: Int32 = Int32(15 << 16)

/// 透過 IOHIDEventSystemClient 讀溫度感測器,依名稱前綴歸類 CPU/GPU 取平均。
public struct IOHIDThermalSource: ThermalSource {
    public init() {}

    public func read() -> ThermalReading? {
        let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005]
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClientRef] else {
            return nil
        }

        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        for service in services {
            guard let nameRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
                  let name = nameRef as? String else { continue }
            guard let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperature)
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
    /// `PMU tdie*`(矽晶 die 溫度,作為 CPU/SoC 代表);
    /// 板級 `tdev*`、校正 `tcal`、`gas gauge battery`、`NAND` 等非 die 感測器排除,
    /// 以免拉低或污染均值。Intel/其他硬體若出現含 cpu/gpu/soc 的名稱也一併支援。
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
