import SwiftUI
import GlanceCore

/// 列出前幾名 app 記憶體用量:名稱 + 右側 bytes 數值。
struct TopAppMemoryList: View {
    let apps: [AppMemoryUsage]
    let accent: Color

    var body: some View {
        let top = Array(apps.prefix(3))
        let maxVal = max(top.map { Double($0.memoryBytes) }.max() ?? 1.0, 0.0001)

        VStack(spacing: 4) {
            ForEach(top) { app in
                let val = Double(app.memoryBytes)
                let ratio = min(max(val / maxVal, 0.0), 1.0)

                HStack(spacing: 8) {
                    Text(app.appName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(Formatters.bytes(app.memoryBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accent.opacity(0.08))
                            .frame(width: geo.size.width * CGFloat(ratio))
                    }
                }
            }
        }
    }
}
