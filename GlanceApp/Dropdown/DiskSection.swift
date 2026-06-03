import SwiftUI
import GlanceCore

struct DiskSection: View {
    let snapshot: DiskSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("磁碟").font(.headline)
                Spacer()
                if let d = snapshot {
                    Text("\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes))")
                        .monospacedDigit().font(.callout)
                }
            }
            ProgressView(value: snapshot?.usedFraction ?? 0)
                .tint(.yellow)
        }
    }
}
