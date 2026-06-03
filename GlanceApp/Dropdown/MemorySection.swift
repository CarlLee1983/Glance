import SwiftUI
import GlanceCore

struct MemorySection: View {
    let snapshot: MemorySnapshot?
    let history: [Double]
    let topProcesses: [ProcessUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("記憶體").font(.headline)
                Spacer()
                if let m = snapshot {
                    Text("\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes))")
                        .monospacedDigit().font(.callout)
                }
            }
            Sparkline(values: history, maxValue: 1, color: .blue)
                .frame(height: 40)
            TopProcessList(processes: topProcesses) { Formatters.bytes($0.memoryBytes) }
        }
    }
}
