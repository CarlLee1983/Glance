/// 一次取樣全部指標的抽象(可注入測試替身給 MetricsStore)。
public protocol SystemSampling {
    func sample() -> SystemSnapshot
}

/// 組裝所有 Sampler,產出一次 SystemSnapshot。程式列舉只做一次(CPU/記憶體共用)。
public final class SystemSampler: SystemSampling {
    private let cpu: CPUSampler
    private let memory: MemorySampler
    private let network: NetworkSampler
    private let disk: DiskSampler
    private let battery: BatterySampler
    private let process: ProcessSampler

    public init(cpu: CPUSampler, memory: MemorySampler, network: NetworkSampler,
                disk: DiskSampler, battery: BatterySampler, process: ProcessSampler) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.process = process
    }

    /// 以真實系統來源建立。
    public convenience init() {
        self.init(
            cpu: CPUSampler(source: MachCPUSource()),
            memory: MemorySampler(source: MachMemorySource()),
            network: NetworkSampler(source: InterfaceCountersSource()),
            disk: DiskSampler(source: StatfsDiskSource()),
            battery: BatterySampler(source: IOKitBatterySource()),
            process: ProcessSampler(source: LibprocSource(), limit: 5))
    }

    public func sample() -> SystemSnapshot {
        let procs = process.sample()
        return SystemSnapshot(
            cpu: cpu.sample(),
            memory: memory.sample(),
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
            topByCPU: procs.topCPU,
            topByMemory: procs.topMemory)
    }
}
