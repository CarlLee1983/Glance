import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let topApps: [AppMemoryUsage]

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        MetricCard(
            title: "記憶體",
            systemImage: "memorychip",
            accent: .blue,
            value: Formatters.percent(usedFraction),
            detail: memoryDetail,
            status: MetricStatus.capacity(fraction: usedFraction)
        ) {
            Sparkline(values: history, maxValue: 1, color: .blue)
                .frame(height: 42)
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
        return "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes))"
    }
}
