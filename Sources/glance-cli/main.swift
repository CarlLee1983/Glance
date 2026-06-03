import GlanceCore
import Foundation

// 為了讓差值指標(CPU/網路/程式)有第二筆,取樣兩次、中間間隔 1 秒。
let cpu = CPUSampler(source: MachCPUSource())
let memory = MemorySampler(source: MachMemorySource())
let network = NetworkSampler(source: InterfaceCountersSource())
let disk = DiskSampler(source: StatfsDiskSource())
let battery = BatterySampler(source: IOKitBatterySource())
let process = ProcessSampler(source: LibprocSource(), limit: 5)

func sampleAll() -> SystemSnapshot {
    SystemSnapshot(
        cpu: cpu.sample(),
        memory: memory.sample(),
        network: network.sample(),
        disk: disk.sample(),
        battery: battery.sample(),
        topByCPU: process.sampleTopByCPU(),
        topByMemory: process.sampleTopByMemory())
}

_ = sampleAll()                 // 第一筆:建立差值基準
Thread.sleep(forTimeInterval: 1)
let s = sampleAll()

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
    line("電池", "\(Formatters.percent(b.chargeFraction))\(b.isCharging ? " ⚡" : "")")
}
print("\n-- Top CPU --")
for p in s.topByCPU {
    print("  \(Formatters.percent(p.cpuFraction))\t\(p.name)")
}
