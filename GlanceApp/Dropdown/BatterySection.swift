import SwiftUI
import GlanceCore

struct BatterySection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        MetricCard(
            title: "電池",
            systemImage: batteryIcon,
            accent: .mint,
            value: Formatters.percent(snapshot.chargeFraction),
            detail: detailText,
            status: MetricStatus.battery(chargeFraction: snapshot.chargeFraction,
                                         isCharging: snapshot.isCharging)
        ) {
            CustomProgressBar(value: snapshot.chargeFraction, color: .mint)
        }
    }

    /// 主狀態 + 可得進階資訊(只串接有值者)。
    private var detailText: String {
        var parts: [String] = [snapshot.isCharging ? "已連接電源" : "使用電池供電"]
        if let cycles = snapshot.cycleCount { parts.append("循環 \(cycles)") }
        if let health = snapshot.healthFraction { parts.append("健康 \(Formatters.percent(health))") }
        if let watts = snapshot.powerWatts { parts.append(Formatters.watts(watts)) }
        if let temp = snapshot.temperature { parts.append(Formatters.temperature(temp)) }
        return parts.joined(separator: " · ")
    }

    private var batteryIcon: String {
        if snapshot.isCharging { return "battery.100.bolt" }
        if snapshot.chargeFraction < 0.25 { return "battery.25" }
        if snapshot.chargeFraction < 0.75 { return "battery.50" }
        return "battery.100"
    }
}
