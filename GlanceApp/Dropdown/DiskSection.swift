import AppKit
import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?
    let io: DiskIOSnapshot?
    let readHistory: [Double]
    let writeHistory: [Double]
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

            if let io {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text("寫 \(Formatters.rateCompact(io.writeBytesPerSec))/s")
                    Text("·").foregroundStyle(.secondary)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("讀 \(Formatters.rateCompact(io.readBytesPerSec))/s")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            // 讀、寫共用同一 ioMax 以同尺度疊圖可比;max(...,1) 防全 0 除零(兩線貼底)。
            let ioMax = max(readHistory.max() ?? 0, writeHistory.max() ?? 0, 1)
            // z-order 刻意:讀線(淡)在下、寫線(實)在上——寫入為使用者較關注的前景指標。
            ZStack {
                Sparkline(values: readHistory,  maxValue: ioMax, color: .yellow.opacity(0.45))
                Sparkline(values: writeHistory, maxValue: ioMax, color: .yellow)
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
