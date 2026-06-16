import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let pressureHistory: [Double]   // 與 history 等長的壓力序數(0/1/2)
    let topApps: [AppMemoryUsage]

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        let pressure = snapshot?.pressure ?? .normal
        MetricCard(
            title: "記憶體",
            systemImage: "memorychip",
            accent: .blue,
            value: Formatters.percent(usedFraction),
            detail: memoryDetail,
            status: nil,
            valueColor: PressureColor.color(for: pressure)
        ) {
            Sparkline(
                values: history,
                maxValue: 1,
                color: .blue,
                bandColors: pressureBandColors
            )
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if topApps.isEmpty {
                EmptyMetricLine(text: "暫無高記憶體程式")
            } else {
                AppMemoryList(apps: topApps, accent: .blue)
            }
        }
    }

    private var memoryDetail: String {
        guard let m = snapshot else { return "等待記憶體取樣" }
        return "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes)) · 壓力:\(m.pressure.displayLabel)"
    }

    /// 壓力歷史序數映射為顏色;長度與 history 不一致時回傳 nil(Sparkline 退回單色)。
    private var pressureBandColors: [Color]? {
        guard pressureHistory.count == history.count, !pressureHistory.isEmpty else { return nil }
        return pressureHistory.map { PressureColor.color(forLevel: Int($0)) }
    }
}
