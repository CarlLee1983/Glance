import SwiftUI
import GlanceCore

/// 記憶體壓力的活動監視器語義色:綠=正常 / 黃=警告 / 紅=嚴重。
/// 標題數字色與 sparkline 分段色共用此唯一來源。
enum PressureColor {
    static func color(for pressure: MemoryPressure) -> Color {
        color(forLevel: pressure.level)
    }

    /// 供 sparkline 由歷史序數(0/1/2)取色。
    static func color(forLevel level: Int) -> Color {
        switch level {
        case 2: return .red
        case 1: return .yellow
        default: return .green
        }
    }
}
