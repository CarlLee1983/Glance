import SwiftUI
import GlanceCore

/// 選單列常駐標籤:精簡數字。首次出現時啟動取樣計時器,頻率變更時重啟。
struct MenuBarLabel: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"

    private var segments: [MenuBarSegment] {
        segmentsRaw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
    }

    var body: some View {
        Text(MenuBarText.compose(snapshot: store.snapshot, segments: segments))
            .monospacedDigit()
            .task { store.start(interval: refreshInterval) }
            .onChange(of: refreshInterval) { _, newValue in
                store.start(interval: newValue)
            }
    }
}
