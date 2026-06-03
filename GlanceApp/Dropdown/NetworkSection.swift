import SwiftUI
import GlanceCore

struct NetworkSection: View {
    let snapshot: NetworkSnapshot?
    let downHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("網路").font(.headline)
                Spacer()
                if let n = snapshot {
                    Text("↓\(Formatters.rateCompact(n.downBytesPerSec))  ↑\(Formatters.rateCompact(n.upBytesPerSec))")
                        .monospacedDigit().font(.callout)
                }
            }
            Sparkline(values: downHistory, maxValue: nil, color: .orange)
                .frame(height: 40)
        }
    }
}
