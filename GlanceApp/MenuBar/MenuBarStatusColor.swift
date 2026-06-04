import SwiftUI
import GlanceCore

/// App 層的狀態色對應。核心只產生語意狀態,不依賴 SwiftUI 顏色。
enum MenuBarStatusColor {
    static func color(for status: MetricStatus) -> Color {
        switch status {
        case .normal:
            return .secondary
        case .elevated:
            return .orange
        case .critical:
            return .red
        case .charging:
            return .green
        }
    }
}
