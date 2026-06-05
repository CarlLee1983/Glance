import AppKit
import SwiftUI
import GlanceCore

/// 按 app 彙總的記憶體排行:第一名以較大列、app 圖示、「最佔用」標籤凸顯。
/// 預設顯示前 `collapsedCount` 名,可展開看更多。
struct AppMemoryList: View {
    let apps: [AppMemoryUsage]
    let accent: Color

    @State private var expanded = false

    private let collapsedCount = 5

    var body: some View {
        let visibleCount = expanded ? apps.count : min(collapsedCount, apps.count)
        let visible = Array(apps.prefix(visibleCount))
        let maxVal = max(Double(apps.first?.memoryBytes ?? 1), 0.0001)

        VStack(spacing: 5) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, app in
                row(app, isTop: index == 0, maxVal: maxVal)
            }

            if apps.count > collapsedCount {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(expanded ? "收合" : "顯示全部 \(apps.count) 個")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
