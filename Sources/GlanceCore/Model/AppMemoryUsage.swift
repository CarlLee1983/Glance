import Foundation

/// 對外呈現的「按 app 彙總」記憶體用量。memoryBytes 為該 app 所有行程 phys_footprint 加總。
public struct AppMemoryUsage: Equatable, Identifiable {
    public let id: String          // 群組鍵(bundle 路徑或行程名)
    public let appName: String
    public let bundleURL: URL?     // 給 app 層抓圖示;非 app 為 nil
    public let memoryBytes: UInt64
    public let processCount: Int
    public init(id: String, appName: String, bundleURL: URL?, memoryBytes: UInt64, processCount: Int) {
        self.id = id; self.appName = appName; self.bundleURL = bundleURL
        self.memoryBytes = memoryBytes; self.processCount = processCount
    }
}
