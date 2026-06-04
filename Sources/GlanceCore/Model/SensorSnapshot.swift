/// 感測值彙整。每欄獨立可缺漏:對應來源失敗 → nil / 空陣列(故障隔離)。
public struct SensorSnapshot: Equatable {
    public let cpuTemperature: Double?   // °C
    public let gpuTemperature: Double?   // °C
    public let systemPower: Double?      // W(SoC 總功耗)
    public let cpuPower: Double?         // W
    public let gpuPower: Double?         // W
    public let fanRPM: [Int]             // 無風扇 → []

    public init(cpuTemperature: Double? = nil, gpuTemperature: Double? = nil,
                systemPower: Double? = nil, cpuPower: Double? = nil,
                gpuPower: Double? = nil, fanRPM: [Int] = []) {
        self.cpuTemperature = cpuTemperature; self.gpuTemperature = gpuTemperature
        self.systemPower = systemPower; self.cpuPower = cpuPower
        self.gpuPower = gpuPower; self.fanRPM = fanRPM
    }

    /// 五個感測欄位皆 nil 且無風扇轉速 → 視為整體無感測器(UI 整區隱藏)。
    public var isEmpty: Bool {
        cpuTemperature == nil && gpuTemperature == nil && systemPower == nil
            && cpuPower == nil && gpuPower == nil && fanRPM.isEmpty
    }
}

/// 溫度來源讀數。
public struct ThermalReading: Equatable {
    public let cpu: Double?
    public let gpu: Double?
    public init(cpu: Double?, gpu: Double?) { self.cpu = cpu; self.gpu = gpu }
}

/// 功耗來源讀數(瓦)。
public struct PowerReading: Equatable {
    public let system: Double?
    public let cpu: Double?
    public let gpu: Double?
    public init(system: Double?, cpu: Double?, gpu: Double?) {
        self.system = system; self.cpu = cpu; self.gpu = gpu
    }
}

public protocol ThermalSource { func read() -> ThermalReading? }
public protocol PowerSource { func read() -> PowerReading? }
public protocol FanSource { func read() -> [Int] }
