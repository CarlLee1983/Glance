import GlanceCore
import Foundation

let sampler = SystemSampler()
_ = sampler.sample()            // 第一筆:建立差值基準
Thread.sleep(forTimeInterval: 1)
let s = sampler.sample()

func line(_ label: String, _ value: String) {
    print("\(label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(value)")
}

print("=== Glance ===")
if let c = s.cpu { line("CPU", Formatters.percent(c.totalUsage)) }
if let m = s.memory {
    line("記憶體", "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes)) (\(Formatters.percent(m.usedFraction)))")
}
if let n = s.network {
    line("網路", "↓\(Formatters.rateCompact(n.downBytesPerSec)) ↑\(Formatters.rateCompact(n.upBytesPerSec))")
}
if let d = s.disk {
    line("磁碟", "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes)) (\(Formatters.percent(d.usedFraction)))")
}
if let b = s.battery, b.isPresent {
    var extra: [String] = []
    if let c = b.cycleCount { extra.append("循環\(c)") }
    if let h = b.healthFraction { extra.append("健康\(Formatters.percent(h))") }
    if let w = b.powerWatts { extra.append(Formatters.watts(w)) }
    if let t = b.temperature { extra.append(Formatters.temperature(t)) }
    let suffix = extra.isEmpty ? "" : "  [\(extra.joined(separator: " "))]"
    line("電池", "\(Formatters.percent(b.chargeFraction))\(b.isCharging ? " ⚡" : "")\(suffix)")
}
if let sensor = s.sensors {
    print("\n-- 感測器 --")
    if let t = sensor.cpuTemperature { line("CPU 溫", Formatters.temperature(t)) }
    if let t = sensor.gpuTemperature { line("GPU 溫", Formatters.temperature(t)) }
    if let p = sensor.systemPower { line("功耗", Formatters.watts(p)) }
    if !sensor.fanRPM.isEmpty {
        line("風扇", sensor.fanRPM.map { "\($0) RPM" }.joined(separator: " / "))
    }
}
print("\n-- Top CPU --")
for p in s.topByCPU {
    print("  \(Formatters.percent(p.cpuFraction))\t\(p.name)")
}
