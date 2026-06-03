import Foundation

/// 集中所有人類可讀字串轉換,純函式、可測試。
public enum Formatters {
    /// 0...1 分數 → "23%"。
    public static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return "\(Int((clamped * 100).rounded()))%"
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
}
