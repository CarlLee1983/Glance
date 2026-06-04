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
            detail: snapshot.isCharging ? "已連接電源" : "使用電池供電",
            status: MetricStatus.battery(chargeFraction: snapshot.chargeFraction,
                                         isCharging: snapshot.isCharging)
        ) {
            CustomProgressBar(value: snapshot.chargeFraction, color: .mint)
        }
    }

    private var batteryIcon: String {
        if snapshot.isCharging { return "battery.100.bolt" }
        if snapshot.chargeFraction < 0.25 { return "battery.25" }
        if snapshot.chargeFraction < 0.75 { return "battery.50" }
        return "battery.100"
    }
}
