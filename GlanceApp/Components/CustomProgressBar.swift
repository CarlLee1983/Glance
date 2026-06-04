import SwiftUI

/// 自訂極簡進度條,支援漸層色與圓角 Capsule 設計
struct CustomProgressBar: View {
    let value: Double // 0.0 ~ 1.0
    let color: Color

    var body: some View {
        let clampedValue = min(max(value, 0.0), 1.0)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(clampedValue))
            }
        }
        .frame(height: 5)
    }
}
