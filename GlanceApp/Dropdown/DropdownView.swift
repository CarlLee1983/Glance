import SwiftUI
import GlanceCore

/// 點開選單列後的詳情視圖:各指標區塊 + 設定 / 結束。
struct DropdownView: View {
    @ObservedObject var store: MetricsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 0) {
            header(snapshot: s)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    CPUSection(snapshot: s?.cpu,
                               history: store.history.cpu.elements,
                               topProcesses: s?.topByCPU ?? [])
                    MemorySection(snapshot: s?.memory,
                                  history: store.history.memory.elements,
                                  topApps: s?.topMemoryApps ?? [])
                    NetworkSection(snapshot: s?.network,
                                   downHistory: store.history.netDown.elements)
                    DiskSection(snapshot: s?.disk)
                    if let b = s?.battery, b.isPresent {
                        BatterySection(snapshot: b)
                    }
                    if let sensors = s?.sensors, !sensors.isEmpty {
                        SensorsSection(snapshot: sensors)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: maxScrollHeight)

            Divider()
                .padding(.horizontal, 12)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    /// 中間捲動區的高度上限:扣掉 header / footer / 螢幕邊距後可用的高度,
    /// 確保整個視窗不會超出可視範圍。內容不足時 ScrollView 會自動縮短,不出現捲軸。
    private var maxScrollHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        // 預留:header(~72) + footer/divider(~52) + 上下與選單列邊距(~96)
        let reserved: CGFloat = 220
        return max(240, screenHeight - reserved)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                openSettingsWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                    Text("設定")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                    Text("結束")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.red.opacity(0.15), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.9))
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func openSettingsWindow() {
        openSettings()
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows
                .filter { $0.isVisible && $0.canBecomeKey }
                .forEach { $0.orderFrontRegardless() }
        }
    }

    private func header(snapshot: SystemSnapshot?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Glance")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(snapshot == nil ? "等待第一次取樣" : "即時系統狀態")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                summaryPill("CPU", value: Formatters.percent(snapshot?.cpu?.totalUsage ?? 0))
                summaryPill("MEM", value: Formatters.percent(snapshot?.memory?.usedFraction ?? 0))
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func summaryPill(_ title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 48, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
