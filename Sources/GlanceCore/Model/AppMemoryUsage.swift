import Foundation

/// 對外呈現的「按 app 彙總」記憶體用量。memoryBytes 為該群組所有行程 phys_footprint 加總。
public struct AppMemoryUsage: Equatable, Identifiable {
    /// 出身分類:這一列的執行檔「住在哪」,純由路徑判定,不涉及可否結束。
    /// 可否結束是另一條獨立的線(見 GlanceApp 結束鈕的 running-apps 判準)。
    public enum Kind: Equatable {
        case app           // 頂層 .app
        case appChild      // 巢狀在另一個 .app 內的 helper(如 Chrome Renderer),隨母體結束
        case systemService // Apple 系統目錄下的服務 / daemon
        case userProcess   // 有執行檔、非 app、非 Apple 系統目錄的其餘行程(CLI 工具、第三方 daemon…)
        case unknown       // 取不到執行檔路徑
    }

    public let id: String          // 群組鍵(bundle 路徑或執行檔路徑)
    public let appName: String
    public let bundleURL: URL?     // 給 app 層抓圖示;非 app 為 nil
    public let memoryBytes: UInt64
    public let processCount: Int
    public let kind: Kind
    public let executablePath: String?   // 群組代表執行檔路徑(非 app 群組成員皆同);取不到為 nil
    public let soloPID: Int32?           // 僅單行程群組才有值,供指認 / 複製 pid 用;多行程為 nil

    public init(id: String,
                appName: String,
                bundleURL: URL?,
                memoryBytes: UInt64,
                processCount: Int,
                kind: Kind,
                executablePath: String?,
                soloPID: Int32?) {
        self.id = id; self.appName = appName; self.bundleURL = bundleURL
        self.memoryBytes = memoryBytes; self.processCount = processCount
        self.kind = kind
        self.executablePath = executablePath
        self.soloPID = soloPID
    }
}
