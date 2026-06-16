/// 選單列上可顯示的欄位。allCases 的順序即為預設顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, diskIO, battery, cpuTemp, power
}

/// 選單列呈現模式。
public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconValue  // 圖示 + 數值
    case iconOnly   // 狀態圖示;raw value 保留以維持 UserDefaults 相容
}

/// 單一欄位的選單列讀數:欄位身分 + 已格式化數值 + 粗略狀態。
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public let status: MetricStatus

    public init(segment: MenuBarSegment, value: String, status: MetricStatus) {
        self.segment = segment
        self.value = value
        self.status = status
    }
}

/// 依選定欄位與順序,把 snapshot 轉成有序讀數。圖示與排版交由 App 層。
/// snapshot 為 nil、欄位資料缺漏、或電池不存在時,該筆略過。
public enum MenuBarText {
    public static func readings(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> [SegmentReading] {
        guard let snapshot else { return [] }
        var result: [SegmentReading] = []
        for seg in segments {
            switch seg {
            case .cpu:
                if let c = snapshot.cpu {
                    result.append(SegmentReading(
                        segment: .cpu,
                        value: Formatters.percent(c.totalUsage),
                        status: MetricStatus.load(fraction: c.totalUsage)
                    ))
                }
            case .memory:
                if let m = snapshot.memory {
                    result.append(SegmentReading(
                        segment: .memory,
                        value: Formatters.percent(m.usedFraction),
                        status: MetricStatus.capacity(fraction: m.usedFraction)
                    ))
                }
            case .network:
                if let n = snapshot.network {
                    result.append(SegmentReading(
                        segment: .network,
                        value: Formatters.rateCompact(n.downBytesPerSec),
                        status: .normal
                    ))
                }
            case .disk:
                if let d = snapshot.disk {
                    result.append(SegmentReading(
                        segment: .disk,
                        value: Formatters.percent(d.usedFraction),
                        status: MetricStatus.capacity(fraction: d.usedFraction)
                    ))
                }
            case .diskIO:
                if let io = snapshot.diskIO {
                    result.append(SegmentReading(
                        segment: .diskIO,
                        value: Formatters.rateCompact(io.writeBytesPerSec),
                        status: .normal
                    ))
                }
            case .battery:
                if let b = snapshot.battery, b.isPresent {
                    result.append(SegmentReading(
                        segment: .battery,
                        value: Formatters.percent(b.chargeFraction),
                        status: MetricStatus.battery(
                            chargeFraction: b.chargeFraction,
                            isCharging: b.isCharging
                        )
                    ))
                }
            case .cpuTemp:
                if let t = snapshot.sensors?.cpuTemperature {
                    result.append(SegmentReading(
                        segment: .cpuTemp,
                        value: Formatters.temperature(t),
                        status: MetricStatus.temperature(celsius: t)
                    ))
                }
            case .power:
                if let p = snapshot.sensors?.systemPower {
                    result.append(SegmentReading(
                        segment: .power,
                        value: Formatters.watts(p),
                        status: .normal
                    ))
                }
            }
        }
        return result
    }
}
