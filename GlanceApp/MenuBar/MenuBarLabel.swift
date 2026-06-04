import SwiftUI
import GlanceCore

/// 選單列常駐標籤:依顯示模式呈現「圖示+數值」或「僅圖示」。
/// 首次出現時啟動取樣計時器,頻率變更時重啟。
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
        content
            .monospacedDigit()
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }

    /// 以單一 `Text` 內插 SF Symbol —— `MenuBarExtra` label 最可靠的渲染方式。
    private var content: Text {
        let readings = MenuBarText.readings(snapshot: store.snapshot, segments: segments)
        guard !readings.isEmpty else { return Text(verbatim: "—") }
        var result = Text(verbatim: "")
        for (i, r) in readings.enumerated() {
            if i > 0 { result = result + Text(verbatim: " ") }
            let icon = Text("\(Image(systemName: MenuBarSegmentIcon.name(for: r.segment)))")
            switch mode {
            case .iconValue: result = result + icon + Text(verbatim: " " + r.value)
            case .iconOnly:  result = result + icon
            }
        }
        return result
    }
}
