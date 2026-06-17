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

        Window("磁碟空間分析", id: "disk-space-analyzer") {
            DiskSpaceAnalyzerWindow()
        }

        Window("清理", id: "cleanup") {
            CleanupView()
        }

        Window("解除安裝", id: "uninstall") {
            UninstallView()
        }

        Settings {
            SettingsView()
        }
    }
}
