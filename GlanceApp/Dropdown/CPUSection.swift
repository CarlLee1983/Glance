import SwiftUI
import GlanceCore

struct CPUSection: View {
    let snapshot: CPUSnapshot?
    let history: [Double]
    let topProcesses: [ProcessUsage]

    var body: some View {
        let usage = snapshot?.totalUsage ?? 0
        MetricCard(
            title: "CPU",
            systemImage: "cpu",
            accent: .green,
            value: Formatters.percent(usage),
            detail: "User \(Formatters.percent(snapshot?.user ?? 0)) · System \(Formatters.percent(snapshot?.system ?? 0))",
            status: MetricStatus.load(fraction: usage)
        ) {
            Sparkline(values: history, maxValue: 1, color: .green)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if topProcesses.isEmpty {
                EmptyMetricLine(text: "暫無高 CPU 程式")
            } else {
                TopProcessList(
                    processes: topProcesses,
                    accent: .green,
                    relativeValue: { $0.cpuFraction },
                    valueText: { Formatters.percentLoose($0.cpuFraction) }
                )
            }
        }
    }
}
