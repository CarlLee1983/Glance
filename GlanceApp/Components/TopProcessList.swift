import SwiftUI
import GlanceCore

/// 列出前幾名程式:名稱 + 右側數值(數值字串由呼叫端決定,CPU 用 percentLoose、記憶體用 bytes)。
struct TopProcessList: View {
    let processes: [ProcessUsage]
    let valueText: (ProcessUsage) -> String

    var body: some View {
        VStack(spacing: 2) {
            ForEach(processes.prefix(3), id: \.pid) { p in
                HStack {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text(valueText(p)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
