import SwiftUI
import GlanceCore

/// 點開選單列後的詳情視圖:各指標區塊 + 設定 / 結束。
struct DropdownView: View {
    @ObservedObject var store: MetricsStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 14) {
            CPUSection(snapshot: s?.cpu,
                       history: store.history.cpu.elements,
                       topProcesses: s?.topByCPU ?? [])
            Divider()
            MemorySection(snapshot: s?.memory,
                          history: store.history.memory.elements,
                          topProcesses: s?.topByMemory ?? [])
            Divider()
            NetworkSection(snapshot: s?.network,
                           downHistory: store.history.netDown.elements)
            Divider()
            DiskSection(snapshot: s?.disk)
            if let b = s?.battery, b.isPresent {
                Divider()
                BatterySection(snapshot: b)
            }
            Divider()
            HStack {
                SettingsLink { Text("設定…") }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
    }
}
