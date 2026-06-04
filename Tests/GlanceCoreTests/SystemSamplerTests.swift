import XCTest
@testable import GlanceCore

private struct FixedCPU: CPUTicksSource {
    func read() -> CPUTicks? { CPUTicks(user: 0, system: 0, idle: 100, nice: 0) }
}
private struct FixedMem: MemoryStatsSource {
    func read() -> MemoryStats? {
        MemoryStats(totalBytes: 16, usedBytes: 8, swapUsedBytes: 0, pressure: .normal)
    }
}
private struct FixedNet: NetworkCountersSource {
    func read() -> NetworkCounters? { NetworkCounters(received: 0, sent: 0) }
}
private struct FixedDisk: DiskStatsSource {
    func read() -> DiskStats? { DiskStats(totalBytes: 100, usedBytes: 40) }
}
private struct FixedBattery: BatteryStatsSource {
    func read() -> BatteryStats? { BatteryStats(isPresent: true, chargeFraction: 0.5, isCharging: false) }
}
private struct FixedProc: RawProcessSource {
    func read() -> [RawProcess]? { [RawProcess(pid: 1, name: "X", cpuTimeSeconds: 0, memoryBytes: 10)] }
}
private struct FixedThermal: ThermalSource {
    func read() -> ThermalReading? { ThermalReading(cpu: 45, gpu: nil) }
}

final class SystemSamplerTests: XCTestCase {
    func testSampleAggregatesAllMetrics() {
        let sampler = SystemSampler(
            cpu: CPUSampler(source: FixedCPU()),
            memory: MemorySampler(source: FixedMem()),
            network: NetworkSampler(source: FixedNet(), clock: { 0 }),
            disk: DiskSampler(source: FixedDisk()),
            battery: BatterySampler(source: FixedBattery()),
            process: ProcessSampler(source: FixedProc(), clock: { 0 }, limit: 5))
        let snap = sampler.sample()
        XCTAssertNotNil(snap.memory)
        XCTAssertEqual(snap.disk?.usedBytes, 40)
        XCTAssertEqual(snap.battery?.chargeFraction, 0.5)
        XCTAssertEqual(snap.topByMemory.first?.name, "X")
    }

    func testSensorsAreWiredThrough() {
        let sampler = SystemSampler(
            cpu: CPUSampler(source: FixedCPU()),
            memory: MemorySampler(source: FixedMem()),
            network: NetworkSampler(source: FixedNet(), clock: { 0 }),
            disk: DiskSampler(source: FixedDisk()),
            battery: BatterySampler(source: FixedBattery()),
            process: ProcessSampler(source: FixedProc(), clock: { 0 }, limit: 5),
            sensor: SensorSampler(thermal: FixedThermal()))
        let snap = sampler.sample()
        XCTAssertEqual(snap.sensors?.cpuTemperature, 45)
    }
}
