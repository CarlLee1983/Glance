import SwiftUI
import GlanceCore

/// 設定:開機自啟、更新頻率、選單列樣式、選單列欄位(可勾選 + 可拖曳排序)。
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("menuBarDisplayMode") private var displayModeRaw: String = MenuBarDisplayMode.iconValue.rawValue
    @StateObject private var loginItem = LoginItemController()

    // 欄位順序與啟用狀態:由 menuBarSegments 種子,持久化時寫回同一鍵(保序)。
    @State private var order: [MenuBarSegment]
    @State private var enabled: Set<MenuBarSegment>

    init() {
        let raw = UserDefaults.standard.string(forKey: "menuBarSegments") ?? "cpu,memory,network"
        let selected = raw.split(separator: ",").compactMap { MenuBarSegment(rawValue: String($0)) }
        let rest = MenuBarSegment.allCases.filter { !selected.contains($0) }
        _order = State(initialValue: selected + rest)
        _enabled = State(initialValue: Set(selected))
    }

    var body: some View {
        Form {
            Section("一般") {
                Toggle("登入時啟動 Glance", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                if let msg = loginItem.errorMessage {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
            Section("更新頻率") {
                Slider(value: $refreshInterval, in: 1...5, step: 1)
                Text("每 \(Int(refreshInterval)) 秒更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列樣式") {
                Picker("樣式", selection: $displayModeRaw) {
                    Text("圖示 + 數值").tag(MenuBarDisplayMode.iconValue.rawValue)
                    Text("狀態圖示").tag(MenuBarDisplayMode.iconOnly.rawValue)
                }
                .pickerStyle(.radioGroup)
                Text("狀態圖示會以顏色呈現各欄位狀態,同時維持最省選單列寬度")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("選單列欄位(拖曳調整順序)") {
                // 巢狀 List 是刻意為之:macOS 上 List 的 .onMove 會原生提供拖曳把手,
                // 不需切換 editMode;固定高度避免與外層 Form 捲動產生視覺衝突。
                List {
                    ForEach(order, id: \.self) { seg in
                        Toggle(label(seg), isOn: Binding(
                            get: { enabled.contains(seg) },
                            set: { on in
                                if on { enabled.insert(seg) } else { enabled.remove(seg) }
                                persist()
                            }))
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        persist()
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// 只把「啟用中」的欄位依目前順序寫回 menuBarSegments(逗號字串保序)。
    /// 用 `UserDefaults.standard.set` 而非 @AppStorage binding:兩者共用同一 suite,
    /// 寫入會傳播給 MenuBarLabel 的 @AppStorage 觀察者,且避免 binding 循環。
    private func persist() {
        let raw = order.filter { enabled.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: "menuBarSegments")
    }

    private func label(_ s: MenuBarSegment) -> String {
        switch s {
        case .cpu:     return "CPU"
        case .memory:  return "記憶體"
        case .network: return "網路"
        case .disk:    return "磁碟"
        case .diskIO:  return "磁碟讀寫"
        case .battery: return "電池"
        case .cpuTemp: return "CPU 溫度"
        case .power:   return "功耗"
        }
    }
}
