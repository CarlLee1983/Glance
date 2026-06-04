/// 選單列上可顯示的欄位。allCases 的順序即為預設顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, battery
}

/// 選單列呈現模式。
public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconValue  // 圖示 + 數值
    case iconOnly   // 僅圖示(最省寬度)
}

/// 單一欄位的選單列讀數:欄位身分 + 已格式化的數值字串(不含圖示/箭頭)。
public struct SegmentReading: Equatable {
    public let segment: MenuBarSegment
    public let value: String
    public init(segment: MenuBarSegment, value: String) {
        self.segment = segment
        self.value = value
    }
}

/// 依選定欄位與順序,把 snapshot 轉成有序讀數。圖示與排版交由 App 層。
/// snapshot 為 nil、欄位資料缺漏、或電池不存在時,該筆略過。
public enum MenuBarText {
    public static func readings(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> [SegmentReading] {
        guard let snapshot else { return [] }
        var out: [SegmentReading] = []
        for seg in segments {
            switch seg {
            case .cpu:
                if let c = snapshot.cpu {
                    out.append(SegmentReading(segment: .cpu, value: Formatters.percent(c.totalUsage)))
                }
            case .memory:
                if let m = snapshot.memory {
                    out.append(SegmentReading(segment: .memory, value: Formatters.percent(m.usedFraction)))
                }
            case .network:
                if let n = snapshot.network {
                    out.append(SegmentReading(segment: .network, value: Formatters.rateCompact(n.downBytesPerSec)))
                }
            case .disk:
                if let d = snapshot.disk {
                    out.append(SegmentReading(segment: .disk, value: Formatters.percent(d.usedFraction)))
                }
            case .battery:
                if let b = snapshot.battery, b.isPresent {
                    out.append(SegmentReading(segment: .battery, value: Formatters.percent(b.chargeFraction)))
                }
            }
        }
        return out
    }
}
