import SwiftUI

@main
struct GlanceApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Glance v0.1")
                .padding(12)
        } label: {
            Text("📊")
        }
        .menuBarExtraStyle(.window)
    }
}
