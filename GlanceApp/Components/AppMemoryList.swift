import AppKit
import SwiftUI
import GlanceCore

/// 按 app 彙總的記憶體排行:第一名以較大列、app 圖示、「最佔用」標籤凸顯。
struct AppMemoryList: View {
    let apps: [AppMemoryUsage]
    let accent: Color

    var body: some View {
        let top = Array(apps.prefix(3))
        let maxVal = max(Double(top.first?.memoryBytes ?? 1), 0.0001)

        VStack(spacing: 5) {
            ForEach(Array(top.enumerated()), id: \.element.id) { index, app in
                row(app, isTop: index == 0, maxVal: maxVal)
            }
        }
    }

    private func row(_ app: AppMemoryUsage, isTop: Bool, maxVal: Double) -> some View {
        let ratio = min(max(Double(app.memoryBytes) / maxVal, 0.0), 1.0)

        return HStack(spacing: 8) {
            icon(for: app)
                .resizable()
                .frame(width: isTop ? 22 : 16, height: isTop ? 22 : 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.appName)
                        .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isTop {
                        Text("最佔用")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(accent.opacity(0.18), in: Capsule())
                    }
                }
                if app.processCount > 1 {
                    Text("\(app.processCount) 個行程")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(Formatters.bytes(app.memoryBytes))
                .font(.system(size: isTop ? 12 : 11, weight: isTop ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isTop ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, isTop ? 5 : 3)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accent.opacity(isTop ? 0.14 : 0.07))
                    .frame(width: geo.size.width * CGFloat(ratio))
            }
        }
    }

    private func icon(for app: AppMemoryUsage) -> Image {
        if let url = app.bundleURL {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app.dashed")
    }
}
