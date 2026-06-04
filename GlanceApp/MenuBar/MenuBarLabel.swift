import SwiftUI
import GlanceCore

/// 選單列常駐標籤:依顯示模式呈現「圖示+數值」或「狀態圖示」。
/// 首次出現時啟動取樣計時器,頻率變更時重啟。
///
/// `MenuBarExtra` label 會丟棄複雜 SwiftUI label 的部分 SF Symbol 呈現,
/// 因此先用 `ImageRenderer` 轉成 `NSImage`。狀態圖示模式必須保留彩色輸出,
/// 不能標成 template image;圖示+數值模式則維持 template,適應系統選單列前景色。
struct MenuBarLabel: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"
    @AppStorage("menuBarDisplayMode") private var displayModeRaw: String = MenuBarDisplayMode.iconValue.rawValue

    private var segments: [MenuBarSegment] {
        segmentsRaw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
    }
    private var mode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRaw) ?? .iconValue
    }

    var body: some View {
        Image(nsImage: renderLabel())
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }

    @MainActor
    private func renderLabel() -> NSImage {
        let readings = MenuBarText.readings(snapshot: store.snapshot, segments: segments)
        let content = HStack(spacing: 6) {
            if readings.isEmpty {
                Text(verbatim: "—")
                    .foregroundStyle(.primary)
            } else {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 2) {
                        Image(systemName: MenuBarSegmentIcon.name(for: r.segment))
                            .foregroundStyle(iconColor(for: r))
                        if mode == .iconValue {
                            Text(r.value)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        image.isTemplate = mode == .iconValue
        return image
    }

    private func iconColor(for reading: SegmentReading) -> Color {
        switch mode {
        case .iconValue:
            return .primary
        case .iconOnly:
            return MenuBarStatusColor.color(for: reading.status)
        }
    }
}
