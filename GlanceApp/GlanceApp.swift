import SwiftUI
import GlanceCore

@main
struct GlanceApp: App {
    @StateObject private var store = MetricsStore(sampler: SystemSampler())

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
