/// 一次取樣的全部指標聚合。任一指標可能取樣失敗 → nil(故障隔離)。
public struct SystemSnapshot {
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let diskIO: DiskIOSnapshot?
    public let battery: BatterySnapshot?
    public let sensors: SensorSnapshot?
    public let topByCPU: [ProcessUsage]
    public let topMemoryApps: [AppMemoryUsage]

    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, diskIO: DiskIOSnapshot? = nil,
                battery: BatterySnapshot?,
                sensors: SensorSnapshot? = nil,
                topByCPU: [ProcessUsage], topMemoryApps: [AppMemoryUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.diskIO = diskIO; self.battery = battery; self.sensors = sensors
        self.topByCPU = topByCPU; self.topMemoryApps = topMemoryApps
    }
}
