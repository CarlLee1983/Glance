import AppKit
import SwiftUI
import GlanceCore

/// 按 app 彙總的記憶體排行:第一名以較大列、app 圖示、「最佔用」標籤凸顯。
/// 預設顯示前 `collapsedCount` 名,可展開看更多。
struct AppMemoryList: View {
    let apps: [AppMemoryUsage]
    let accent: Color

    @State private var expanded = false

    @State private var hoveredID: String?

    private let terminator = AppTerminator()

    private let collapsedCount = 5

    /// 可結束:有 .app bundle 且不是 Glance 自身。
    private func eligible(_ app: AppMemoryUsage) -> Bool {
        guard let url = app.bundleURL else { return false }
        return url.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path
    }

    /// 輕量確認 → graceful terminate。
    private func confirmAndTerminate(_ app: AppMemoryUsage) {
        guard let url = app.bundleURL else { return }
        let alert = NSAlert()
        alert.messageText = "確定要結束「\(app.appName)」嗎?"
        alert.informativeText = "未儲存的資料可能遺失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "結束")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let count = terminator.terminateApp(matching: url)
            guard count > 0 else { return }  // 已自行退出(競態)→ 靜默
            let name = app.appName
            let term = terminator
            // 稍候重查:仍在執行多半是被 launchd/系統託管而自動重啟,或正等待儲存對話框。
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard term.isRunning(matching: url) else { return }
                let warn = NSAlert()
                warn.messageText = "「\(name)」可能無法結束"
                warn.informativeText = "它似乎仍在執行。某些背景程式(例如由系統 / launchd 託管的 agent)會在結束後被自動重新啟動,或它正在等待你回應儲存對話框。"
                warn.alertStyle = .informational
                warn.addButton(withTitle: "好")
                warn.runModal()
            }
        }
    }

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
        let showKill = hoveredID == app.id && eligible(app)

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

            if showKill {
                Button {
                    confirmAndTerminate(app)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("結束「\(app.appName)」")
                .transition(.opacity)
            }

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
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                if inside { hoveredID = app.id }
                else if hoveredID == app.id { hoveredID = nil }
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
