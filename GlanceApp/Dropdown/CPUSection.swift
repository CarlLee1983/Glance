import SwiftUI
import GlanceCore

struct CPUSection: View {
    let snapshot: CPUSnapshot?
    let history: [Double]
    let topProcesses: [ProcessUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU").font(.headline)
                Spacer()
                Text(Formatters.percent(snapshot?.totalUsage ?? 0)).monospacedDigit()
            }
            Sparkline(values: history, maxValue: 1, color: .green)
                .frame(height: 40)
            TopProcessList(processes: topProcesses) { Formatters.percentLoose($0.cpuFraction) }
        }
    }
}
