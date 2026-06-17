import AppKit
import GlanceCore

/// 把 NSRunningApplication 映射成 RunningAppRef 餵給 AppTerminationMatcher,
/// 再對相符者執行 graceful terminate。動作以 closure 注入以利測試/替身。
struct AppTerminator {
    /// 對單一 running app 執行的結束動作(預設 graceful terminate)。
    var terminate: (NSRunningApplication) -> Void = { _ = $0.terminate() }

    /// 列舉目前 running apps(預設取系統清單)。
    var runningApps: () -> [NSRunningApplication] = { NSWorkspace.shared.runningApplications }

    /// 結束所有 bundleURL 與 target 相符且非自身的 running app(同 app 多實例全數結束)。
    /// 找不到相符(例如 App 已自行退出)時為安全 no-op。回傳實際嘗試結束的數量。
    @discardableResult
    func terminateApp(matching target: URL) -> Int {
        let apps = runningApps()
        let refs = apps.compactMap { app -> RunningAppRef? in
            guard let url = app.bundleURL else { return nil }
            return RunningAppRef(bundleURL: url, isCurrentApp: app == .current)
        }
        let wantedPaths = Set(
            AppTerminationMatcher.matches(target: target, running: refs)
                .map { $0.bundleURL.standardizedFileURL.path }
        )
        let toTerminate = apps.filter { app in
            guard let url = app.bundleURL, app != .current else { return false }
            return wantedPaths.contains(url.standardizedFileURL.path)
        }
        toTerminate.forEach { terminate($0) }
        return toTerminate.count
    }
}
