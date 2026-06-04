import GlanceCore

/// 選單列欄位對應的 SF Symbol 名稱。集中於此,方便日後調整圖示。
enum MenuBarSegmentIcon {
    static func name(for segment: MenuBarSegment) -> String {
        switch segment {
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .network: return "arrow.down"
        case .disk:    return "internaldrive"
        case .battery: return "battery.100"
        case .cpuTemp: return "thermometer.medium"
        case .power:   return "bolt"
        }
    }
}
