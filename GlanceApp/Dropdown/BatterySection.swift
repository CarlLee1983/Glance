import SwiftUI
import GlanceCore

struct BatterySection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack {
            Text("電池").font(.headline)
            Spacer()
            Text("\(Formatters.percent(snapshot.chargeFraction))\(snapshot.isCharging ? " ⚡" : "")")
                .monospacedDigit()
        }
    }
}
