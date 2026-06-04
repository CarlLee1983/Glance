/// 組裝溫度/功耗/風扇三來源 → SensorSnapshot。任一來源缺漏只讓該欄為 nil/空;
/// 三者皆無資料 → 回 nil(UI 整區隱藏)。
public final class SensorSampler {
    private let thermal: ThermalSource?
    private let power: PowerSource?
    private let fan: FanSource?

    public init(thermal: ThermalSource? = nil, power: PowerSource? = nil, fan: FanSource? = nil) {
        self.thermal = thermal; self.power = power; self.fan = fan
    }

    public func sample() -> SensorSnapshot? {
        let t = thermal?.read()
        let p = power?.read()
        let f = fan?.read() ?? []
        let snap = SensorSnapshot(
            cpuTemperature: t?.cpu, gpuTemperature: t?.gpu,
            systemPower: p?.system, cpuPower: p?.cpu, gpuPower: p?.gpu,
            fanRPM: f)
        return snap.isEmpty ? nil : snap
    }
}
