import AppKit
import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?
    @Environment(\.openWindow) private var openWindow

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

            Button {
                openAnalyzerWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                    Text("分析空間...")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private var diskDetail: String {
        guard let d = snapshot else { return "等待磁碟取樣" }
        return "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes))"
    }

    private func openAnalyzerWindow() {
        openWindow(id: "disk-space-analyzer")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
