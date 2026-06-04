import Foundation

/// 集中所有人類可讀字串轉換,純函式、可測試。
public enum Formatters {
    /// 0...1 分數 → "23%"。
    public static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// 0... 分數 → 百分比字串,不上限(供多核程式 CPU% 顯示,可 >100%)。
    public static func percentLoose(_ fraction: Double) -> String {
        let v = max(0, fraction)
        return "\(Int((v * 100).rounded()))%"
    }

    /// 位元組 → "9.8 GB" / "5.0 MB"(1024 基底,一位小數)。
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var idx = 0
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(Int(v)) B"
        }
        return String(format: "%.1f %@", v, units[idx])
    }

    /// 速率(bytes/sec)→ 選單列精簡字串 "2.1M" / "3.0K" / "0"。
    public static func rateCompact(_ bytesPerSec: Double) -> String {
        let v = max(0, bytesPerSec)
        if v < 1 { return "0" }
        if v < 1024 { return String(format: "%.0f", v) }
        if v < 1024 * 1024 { return String(format: "%.1fK", v / 1024) }
        return String(format: "%.1fM", v / (1024 * 1024))
    }

    /// 攝氏溫度 → "52°C"(四捨五入到整數度)。
    public static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }

    /// 瓦數 → "12.4 W"(一位小數,以絕對值顯示)。
    /// 以絕對值顯示;電池充放電方向由其他文字(已連接電源/使用電池)表達,故此處不帶正負號。
    public static func watts(_ w: Double) -> String {
        String(format: "%.1f W", abs(w))
    }
}
