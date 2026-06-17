import Foundation

/// running app 的輕量描述,讓比對邏輯與 AppKit 解耦、可單元測試。
public struct RunningAppRef: Equatable {
    public let bundleURL: URL
    public let isCurrentApp: Bool
    public init(bundleURL: URL, isCurrentApp: Bool) {
        self.bundleURL = bundleURL
        self.isCurrentApp = isCurrentApp
    }
}

/// 純比對:給定目標 .app 的 bundleURL 與一組 running app,
/// 回傳「bundleURL 標準化後相符且非自身」的項目(可能多個實例)。
public enum AppTerminationMatcher {
    public static func matches(target: URL, running: [RunningAppRef]) -> [RunningAppRef] {
        let key = target.standardizedFileURL.path
        return running.filter { ref in
            !ref.isCurrentApp && ref.bundleURL.standardizedFileURL.path == key
        }
    }
}
