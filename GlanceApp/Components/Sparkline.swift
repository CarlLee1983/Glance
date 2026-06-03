import SwiftUI

/// 由一串數值畫出迷你折線 + 區域填色。maxValue 為 nil 時以資料最大值自動縮放。
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.15))

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, lineWidth: 1.5)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = min(max(v, 0), maxV)
            let y = size.height - CGFloat(clamped / maxV) * size.height
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }
}
