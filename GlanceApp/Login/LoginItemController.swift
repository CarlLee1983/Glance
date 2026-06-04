import SwiftUI
import ServiceManagement

/// 包裝 `SMAppService.mainApp` 的開機自啟開關。切換失敗時還原狀態並提供錯誤訊息,不靜默吞錯。
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var errorMessage: String?

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "設定登入啟動失敗:\(error.localizedDescription)"
        }
        // 一律以系統實際狀態為準,失敗時開關自動還原。
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }
}
