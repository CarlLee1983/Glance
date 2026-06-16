import SwiftUI

/// 由一串數值畫出平滑折線 + 漸層區域填色。maxValue 為 nil 時以資料最大值自動縮放。
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var color: Color = .green
    /// 每個資料點一色。給定時改為逐段著色(段色取右端點 bandColors[i+1]);nil 維持單色。
    var bandColors: [Color]? = nil

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    // 1. 漸層區域填色:band 模式下用最新樣本的壓力色,否則用單色 color。
                    let fillColor: Color = {
                        if let bands = bandColors, bands.count == values.count, let last = bands.last {
                            return last
                        }
                        return color
                    }()
                    smoothedAreaPath(points: pts, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.22), fillColor.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // 2. 平滑描邊折線:有 bandColors 則逐段著色,否則單色。
                    if let bands = bandColors, bands.count == values.count {
                        // pts 與 values 一對一對應(count >= 2 時 pts.count == values.count),
                        // 故此 guard 同時保證 bands.count == pts.count,下方索引皆安全。
                        ForEach(0..<(pts.count - 1), id: \.self) { i in
                            segmentPath(from: pts[i], to: pts[i + 1])
                                .stroke(
                                    bands[i + 1],
                                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                                )
                        }
                    } else {
                        smoothedPath(points: pts)
                            .stroke(
                                LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                            )
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.06))
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

    /// 單一段(點 p1→p2)的三次貝氏平滑路徑,與 smoothedPath 的控制點公式一致。
    private func segmentPath(from p1: CGPoint, to p2: CGPoint) -> Path {
        var path = Path()
        path.move(to: p1)
        let controlPoint1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3.0, y: p1.y)
        let controlPoint2 = CGPoint(x: p1.x + 2.0 * (p2.x - p1.x) / 3.0, y: p2.y)
        path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        return path
    }

    /// 三次貝氏曲線平滑折線路徑
    private func smoothedPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        path.move(to: points[0])
        
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            let controlPoint1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3.0, y: p1.y)
            let controlPoint2 = CGPoint(x: p1.x + 2.0 * (p2.x - p1.x) / 3.0, y: p2.y)
            path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        }
        return path
    }

    /// 三次貝氏曲線平滑區域填充路徑 (閉合至底部)
    private func smoothedAreaPath(points: [CGPoint], height: CGFloat) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        path.move(to: CGPoint(x: points[0].x, y: height))
        path.addLine(to: points[0])
        
        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i+1]
            let controlPoint1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3.0, y: p1.y)
            let controlPoint2 = CGPoint(x: p1.x + 2.0 * (p2.x - p1.x) / 3.0, y: p2.y)
            path.addCurve(to: p2, control1: controlPoint1, control2: controlPoint2)
        }
        
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
        path.closeSubpath()
        return path
    }
}
