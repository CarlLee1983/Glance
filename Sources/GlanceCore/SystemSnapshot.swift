/// 一次取樣的全部指標聚合。任一指標可能取樣失敗 → nil(故障隔離)。
public struct SystemSnapshot {
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let battery: BatterySnapshot?
    public let topByCPU: [ProcessUsage]
    public let topByMemory: [ProcessUsage]

    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, battery: BatterySnapshot?,
                topByCPU: [ProcessUsage], topByMemory: [ProcessUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery
        self.topByCPU = topByCPU; self.topByMemory = topByMemory
    }
}
