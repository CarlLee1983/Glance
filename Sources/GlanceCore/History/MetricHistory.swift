/// 各指標各一條 RingBuffer<Double>,供下拉的歷史曲線使用。缺值記 0 以維持曲線連續。
public struct MetricHistory {
    public private(set) var cpu: RingBuffer<Double>
    public private(set) var memory: RingBuffer<Double>
    public private(set) var netDown: RingBuffer<Double>
    public private(set) var netUp: RingBuffer<Double>
    public private(set) var memoryPressure: RingBuffer<Double>

    public init(capacity: Int = 90) {
        cpu = RingBuffer(capacity: capacity)
        memory = RingBuffer(capacity: capacity)
        netDown = RingBuffer(capacity: capacity)
        netUp = RingBuffer(capacity: capacity)
        memoryPressure = RingBuffer(capacity: capacity)
    }

    public mutating func record(_ snapshot: SystemSnapshot) {
        cpu.append(snapshot.cpu?.totalUsage ?? 0)
        memory.append(snapshot.memory?.usedFraction ?? 0)
        netDown.append(snapshot.network?.downBytesPerSec ?? 0)
        netUp.append(snapshot.network?.upBytesPerSec ?? 0)
        memoryPressure.append(Double(snapshot.memory?.pressure.level ?? 0))
    }
}
