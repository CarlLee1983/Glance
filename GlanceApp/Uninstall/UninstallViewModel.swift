import AppKit
import Combine
import Foundation
import GlanceCore

@MainActor
final class UninstallViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading      // 掃描 App 一覽
        case list         // 選擇 App
        case building     // 構建計畫(找關聯檔 + 執行中檢查)
        case preview      // 預覽計畫
        case confirming   // 確認 sheet
        case running      // 移到垃圾桶中
        case done         // 完成
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var apps: [InstalledApp] = []
    @Published var searchText: String = ""
    @Published private(set) var plan: UninstallPlan?
    @Published private(set) var selectedAppRunning = false
    @Published private(set) var currentPath: String?
    @Published private(set) var runResult: UninstallRunResult?
    @Published var selectedRelatedFiles: Set<RelatedFile> = []

    private let discovery: AppDiscovery
    private let finder: RelatedFileFinder
    private let uninstaller: Uninstaller
    private let isRunning: @Sendable (String) -> Bool

    private var loadTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var generation = 0

    init(
        discovery: AppDiscovery = AppDiscovery(),
        finder: RelatedFileFinder = RelatedFileFinder(),
        uninstaller: Uninstaller = Uninstaller(),
        isRunning: @escaping @Sendable (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    ) {
        self.discovery = discovery
        self.finder = finder
        self.uninstaller = uninstaller
        self.isRunning = isRunning
    }

    deinit {
        loadTask?.cancel()
        buildTask?.cancel()
        runTask?.cancel()
    }

    // MARK: Derived

    var filteredApps: [InstalledApp] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var canUninstall: Bool { phase == .preview && !selectedAppRunning }

    var selectedTotalBytes: UInt64 {
        guard let plan = plan else { return 0 }
        return plan.app.sizeBytes + selectedRelatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedItemCount: Int {
        guard plan != nil else { return 0 }
        return 1 + selectedRelatedFiles.count
    }

    // MARK: Actions

    func load() {
        loadTask?.cancel()
        generation += 1
        let generation = generation
        phase = .loading
        apps = []
        loadTask = Task { [weak self, discovery] in
            let result = await discovery.discover()
            await self?.applyApps(result, generation: generation)
        }
    }

    func select(_ app: InstalledApp) {
        buildTask?.cancel()
        generation += 1
        let generation = generation
        phase = .building
        plan = nil
        currentPath = nil
        buildTask = Task { [weak self, finder, isRunning] in
            let related = await finder.find(bundleID: app.bundleID)
            let running = isRunning(app.bundleID)
            let plan = UninstallPlan(app: app, relatedFiles: related)
            await self?.applyPlan(plan, running: running, generation: generation)
        }
    }

    func backToList() {
        guard phase == .preview || phase == .done else { return }
        buildTask?.cancel()
        runTask?.cancel()
        generation += 1
        plan = nil
        selectedRelatedFiles = []
        runResult = nil
        currentPath = nil
        selectedAppRunning = false
        phase = .list
    }

    func requestConfirmation() {
        guard phase == .preview, !selectedAppRunning else { return }
        phase = .confirming
    }

    func cancelConfirmation() {
        guard phase == .confirming else { return }
        phase = .preview
    }

    func toggleRelatedFile(_ file: RelatedFile) {
        if selectedRelatedFiles.contains(file) {
            selectedRelatedFiles.remove(file)
        } else {
            selectedRelatedFiles.insert(file)
        }
    }

    func confirmUninstall() {
        guard phase == .confirming, let plan else { return }
        // App 可能在預覽後才被啟動;移到垃圾桶前重新確認,執行中則退回預覽顯示警告。
        guard !isRunning(plan.app.bundleID) else {
            selectedAppRunning = true
            phase = .preview
            return
        }
        runTask?.cancel()
        generation += 1
        let generation = generation
        phase = .running
        currentPath = nil
        // Build plan containing only selected related files
        let filteredPlan = UninstallPlan(app: plan.app, relatedFiles: Array(selectedRelatedFiles))
        runTask = Task { [weak self, uninstaller] in
            let result = await uninstaller.run(plan: filteredPlan) { [weak self] progress in
                await self?.applyRunProgress(progress, generation: generation)
            }
            await self?.applyRunResult(result, generation: generation)
        }
    }

    // MARK: Apply (MainActor)

    private func applyApps(_ result: [InstalledApp], generation: Int) {
        guard generation == self.generation else { return }
        apps = result
        phase = .list
        loadTask = nil
    }

    private func applyPlan(_ plan: UninstallPlan, running: Bool, generation: Int) {
        guard generation == self.generation else { return }
        self.plan = plan
        self.selectedRelatedFiles = Set(plan.relatedFiles)
        selectedAppRunning = running
        phase = .preview
        buildTask = nil
    }

    private func applyRunProgress(_ progress: UninstallProgress, generation: Int) {
        guard generation == self.generation, phase == .running else { return }
        currentPath = progress.currentPath
    }

    private func applyRunResult(_ result: UninstallRunResult, generation: Int) {
        guard generation == self.generation else { return }
        runResult = result
        currentPath = nil
        phase = .done
        runTask = nil
    }
}
