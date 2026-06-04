import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?

    var body: some View {
        let usedFraction = snapshot?.usedFraction ?? 0
        MetricCard(
            title: "磁碟",
            systemImage: "internaldrive",
            accent: .yellow,
            value: Formatters.percent(usedFraction),
            detail: diskDetail,
            status: MetricStatus.capacity(fraction: usedFraction)
        ) {
            CustomProgressBar(value: usedFraction, color: .yellow)
        }
    }

    private var diskDetail: String {
        guard let d = snapshot else { return "等待磁碟取樣" }
        return "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes))"
    }
}
