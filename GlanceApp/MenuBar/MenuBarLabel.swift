import SwiftUI
import GlanceCore

/// 選單列常駐標籤:依顯示模式呈現「圖示+數值」或「僅圖示」。
/// 首次出現時啟動取樣計時器,頻率變更時重啟。
///
/// 為何用 `ImageRenderer` 點陣化?`MenuBarExtra` 只會把 `Text` label 當成
/// 狀態列按鈕標題渲染,會丟棄內插在文字裡的 SF Symbol 圖示。把整個
/// `HStack { Image; Text }` 渲染成 template `NSImage` 再交給 label,
/// 圖示與文字才會一起正確顯示,並自動適應淺色/深色選單列。
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

    /// 把目前讀數渲染成 template 圖,確保圖示與數字都顯示於選單列。
    @MainActor
    private func renderLabel() -> NSImage {
        let readings = MenuBarText.readings(snapshot: store.snapshot, segments: segments)
        let content = HStack(spacing: 6) {
            if readings.isEmpty {
                Text(verbatim: "—")
            } else {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 2) {
                        Image(systemName: MenuBarSegmentIcon.name(for: r.segment))
                        if mode == .iconValue {
                            Text(r.value).monospacedDigit()
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        image.isTemplate = true
        return image
    }
}
