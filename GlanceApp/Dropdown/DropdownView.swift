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
                .padding(.bottom, 8)

            HealthBanner(snapshot: s)
                .padding(.horizontal, 12)
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
            .frame(height: scrollHeight)

            Divider()
                .padding(.horizontal, 12)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 440)
        .background(.regularMaterial)
    }

    /// 中間捲動區的固定高度:讓整個視窗一律約為螢幕可視高度的 4/5。
    /// 內容不足時下方留白,內容過長時出現捲軸,視窗高度不隨內容變動。
    private var scrollHeight: CGFloat {
        // 選單列 app 多半沒有 key window,NSScreen.main 可能為 nil,退回有選單列的主螢幕。
        let screen = NSScreen.main ?? NSScreen.screens.first
        let available = screen?.visibleFrame.height ?? 800
        // 視窗整體目標高度 = 可視高度的 4/5;捲動區再扣掉 header(~66) + footer/divider(~54)。
        let chrome: CGFloat = 120
        let target = available * 0.8 - chrome
        return max(360, target)
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
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 56, height: 36)
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
