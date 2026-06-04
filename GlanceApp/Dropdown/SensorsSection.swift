import SwiftUI
import GlanceCore

/// 感測器區:CPU 溫度為主值,其餘可得讀數(GPU 溫/功耗/風扇)以列呈現。
/// 整體無資料時由呼叫端(DropdownView)不渲染本區。
struct SensorsSection: View {
    let snapshot: SensorSnapshot

    var body: some View {
        MetricCard(
            title: "感測器",
            systemImage: "thermometer.medium",
            accent: .orange,
            value: primaryValue,
            detail: "即時感測讀數",
            status: primaryStatus
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if let t = snapshot.gpuTemperature {
                    row("GPU 溫度", Formatters.temperature(t))
                }
                if let p = snapshot.systemPower {
                    row("功耗", Formatters.watts(p))
                }
                if !snapshot.fanRPM.isEmpty {
                    let value = snapshot.fanRPM.map { "\($0) RPM" }.joined(separator: " / ")
                    row("風扇", value)
                }
            }
        }
    }

    /// 主值優先 CPU 溫度,否則功耗,否則第一個風扇轉速,否則 —。
    private var primaryValue: String {
        if let t = snapshot.cpuTemperature { return Formatters.temperature(t) }
        if let p = snapshot.systemPower { return Formatters.watts(p) }
        if let f = snapshot.fanRPM.first { return "\(f) RPM" }
        return "—"
    }

    private var primaryStatus: MetricStatus {
        if let t = snapshot.cpuTemperature { return MetricStatus.temperature(celsius: t) }
        return .normal
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }
}
