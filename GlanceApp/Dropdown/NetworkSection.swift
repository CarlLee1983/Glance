import SwiftUI
import GlanceCore

struct NetworkSection: View {
    let snapshot: NetworkSnapshot?
    let downHistory: [Double]

    var body: some View {
        MetricCard(
            title: "網路",
            systemImage: "network",
            accent: .orange,
            value: snapshot.map { "↓\(Formatters.rateCompact($0.downBytesPerSec))" } ?? "—",
            detail: networkDetail,
            status: nil
        ) {
            Sparkline(values: downHistory, maxValue: nil, color: .orange)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var networkDetail: String {
        guard let n = snapshot else { return "等待網路取樣" }
        return "上傳 \(Formatters.rateCompact(n.upBytesPerSec))/s · 下載 \(Formatters.rateCompact(n.downBytesPerSec))/s"
    }
}
