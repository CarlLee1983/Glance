import SwiftUI
import GlanceCore

/// 設定:更新頻率(1~5 秒)與選單列要顯示哪幾格。皆以 @AppStorage 持久化。
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarSegments") private var segmentsRaw: String = "cpu,memory,network"

    private var selected: Set<String> {
        Set(segmentsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        Form {
            Section("更新頻率") {
                Slider(value: $refreshInterval, in: 1...5, step: 1)
                Text("每 \(Int(refreshInterval)) 秒更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列顯示") {
                ForEach(MenuBarSegment.allCases, id: \.self) { seg in
                    Toggle(label(seg), isOn: Binding(
                        get: { selected.contains(seg.rawValue) },
                        set: { isOn in
                            var set = selected
                            if isOn { set.insert(seg.rawValue) } else { set.remove(seg.rawValue) }
                            segmentsRaw = MenuBarSegment.allCases
                                .filter { set.contains($0.rawValue) }
                                .map(\.rawValue)
                                .joined(separator: ",")
                        }))
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func label(_ s: MenuBarSegment) -> String {
        switch s {
        case .cpu: return "CPU"
        case .memory: return "記憶體"
        case .network: return "網路"
        }
    }
}
