import SwiftUI
import GlanceCore

/// 記憶體壓力的活動監視器語義色:綠=正常 / 黃=警告 / 紅=嚴重。
/// 標題數字色與 sparkline 分段色共用此唯一來源。
enum PressureColor {
    static func color(for pressure: MemoryPressure) -> Color {
        color(forLevel: pressure.level)
    }

    /// 供 sparkline 由歷史序數(0/1/2)取色。
    /// 警告色用系統橘(深淺模式自適應、淺底對比優於 .yellow)。
    static func color(forLevel level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1: return Color(.systemOrange)
        case 2: return .red
        default:
            assertionFailure("非預期的記憶體壓力序數 \(level);預期 0(正常)/1(警告)/2(嚴重)")
            return .green
        }
    }
}
