import SwiftUI
import GlanceCore

/// 列出前幾名程式:名稱 + 右側數值(數值字串由呼叫端決定,CPU 用 percentLoose、記憶體用 bytes)。
struct TopProcessList: View {
    let processes: [ProcessUsage]
    let accent: Color
    let relativeValue: (ProcessUsage) -> Double
    let valueText: (ProcessUsage) -> String

    var body: some View {
        let maxVal = max(processes.prefix(3).map(relativeValue).max() ?? 1.0, 0.0001)

        VStack(spacing: 4) {
            ForEach(processes.prefix(3), id: \.pid) { p in
                let val = relativeValue(p)
                let ratio = min(max(val / maxVal, 0.0), 1.0)

                HStack(spacing: 8) {
                    Text(p.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(valueText(p))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accent.opacity(0.08))
                            .frame(width: geo.size.width * CGFloat(ratio))
                    }
                }
            }
        }
    }
}
