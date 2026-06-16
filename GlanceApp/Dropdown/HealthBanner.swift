import SwiftUI
import GlanceCore

/// 下拉頂端的系統健康橫幅:彩色圓點 + 標籤 + 大號分數。
/// snapshot == nil(尚未取樣)時為灰色,標籤顯示「尚未取樣」、分數顯示「—」。
struct HealthBanner: View {
    let snapshot: SystemSnapshot?

    var body: some View {
        let score = snapshot.map { HealthScoreCalculator.evaluate($0) }
        let color = score?.band.tint ?? .secondary

        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(score?.band.label ?? "尚未取樣")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(score.map { String($0.value) } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        }
    }
}

extension HealthBand {
    /// 分段對應顏色:綠 / 淡綠 / 橘 / 紅。
    var tint: Color {
        switch self {
        case .excellent: return .green
        case .good: return Color(red: 0.40, green: 0.78, blue: 0.45)
        case .fair: return .orange
        case .needsAttention: return .red
        }
    }
}
