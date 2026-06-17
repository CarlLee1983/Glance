import AppKit
import Combine
import Foundation
import GlanceCore

@MainActor
final class DiskSpaceAnalyzerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case completed
        case loadedFromCache
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var scannedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var currentPath: String?
    @Published private(set) var navigator: DiskTreeNavigator?
    @Published private(set) var lastScannedAt: Date?
    @Published var selection: Set<String> = []

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastPublishedAt: Date?
    private let analyzer: DiskSpaceAnalyzer
    private let cache: DiskScanCache
    private let trashService: DiskTrashService
    private let publishInterval: TimeInterval = 0.2

    init(
        analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer(),
        cache: DiskScanCache = DiskScanCache(),
        trashService: DiskTrashService = DiskTrashService()
    ) {
        self.analyzer = analyzer
        self.cache = cache
        self.trashService = trashService
    }

    deinit { scanTask?.cancel() }

    // MARK: - Derived state

    var isScanning: Bool { phase == .scanning }
    var currentNode: DiskNode? { navigator?.currentNode }
    var currentChildren: [DiskNode] { navigator?.currentNode.children ?? [] }
    var breadcrumb: [DiskNode] { navigator?.breadcrumb ?? [] }
    var currentFolderSize: UInt64 { navigator?.currentNode.sizeBytes ?? 0 }
    var canGoUp: Bool { navigator?.canGoUp ?? false }

    var selectedItems: [DiskNode] {
        currentChildren.filter { selection.contains($0.id) }
    }
    var selectedTotalBytes: UInt64 {
        selectedItems.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    var availableDiskBytes: UInt64 {
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    var statusText: String {
        switch phase {
        case .idle: return "準備掃描"
        case .scanning: return "掃描中…"
        case .completed: return "掃描完成"
        case .loadedFromCache: return "讀取自快取"
        case .cancelled: return "已取消"
        }
    }

    var lastScannedText: String? {
        guard let lastScannedAt else { return nil }
        return "上次掃描於 \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard phase == .idle else { return }
        if let entry = cache.load(rootURL: rootURL) {
            navigator = DiskTreeNavigator(root: entry.root)
            lastScannedAt = entry.scannedAt
            phase = .loadedFromCache
        } else {
            startScan()
        }
    }

    func startScan() {
        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        resetForScan()

        let root = rootURL
        scanTask = Task { [weak self, analyzer] in
            let result = await analyzer.scanTree(rootURL: root) { [weak self] progress in
                await self?.apply(progress, generation: generation)
            }
            await self?.apply(result, generation: generation)
        }
    }

    func cancelScan() { scanTask?.cancel() }

    func chooseRoot(_ url: URL) {
        rootURL = url
        selection = []
        navigator = nil
        phase = .idle
        onAppear()
    }

    // MARK: - Navigation

    func drill(into node: DiskNode) {
        guard var nav = navigator, node.isDrillable else { return }
        nav.drill(into: node)
        navigator = nav
        selection = []
    }

    func jump(toDepth depth: Int) {
        guard var nav = navigator else { return }
        nav.jump(toDepth: depth)
        navigator = nav
        selection = []
    }

    func goUp() {
        guard var nav = navigator else { return }
        nav.goUp()
        navigator = nav
        selection = []
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func clearSelection() { selection = [] }

    // MARK: - Trash

    func moveSelectedToTrash() {
        // 鎖定派工當下的選取項目:刪除在背景執行,期間使用者可能下鑽/改選取,
        // 故移除哪些節點必須以這份快照為準,不能在回呼時重讀 live 的 selectedItems。
        let dispatched = selectedItems
        let items = dispatched.map { DiskTrashRequestItem(url: $0.url, sizeBytes: $0.sizeBytes) }
        guard !items.isEmpty, navigator != nil else { return }
        let dispatchedIDs = Set(dispatched.map(\.id))
        let root = rootURL
        let trashService = self.trashService

        Task { [weak self] in
            let result = await Task.detached { trashService.run(items: items, withinRoot: root) }.value
            await self?.applyTrashResult(result, dispatchedIDs: dispatchedIDs)
        }
    }

    private func applyTrashResult(_ result: DiskTrashResult, dispatchedIDs: Set<String>) {
        guard var nav = navigator else { return }
        // DiskNode.id == url.path,故可用被跳過的 url.path 從派工快照中扣除真正被丟掉的項目。
        let skippedIDs = Set(result.skippedPaths.map(\.url.path))
        nav.remove(ids: dispatchedIDs.subtracting(skippedIDs))
        navigator = nav
        selection = []
        persistCache(root: nav.root)
    }

    // MARK: - Helpers

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resetForScan() {
        phase = .scanning
        scannedCount = 0
        skippedCount = 0
        currentPath = nil
        navigator = nil
        selection = []
        lastPublishedAt = nil
    }

    private func apply(_ progress: DiskTreeScanProgress, generation: Int) {
        guard generation == scanGeneration, shouldPublish() else { return }
        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
    }

    private func apply(_ result: DiskTreeScanResult, generation: Int) {
        guard generation == scanGeneration else { return }
        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        scanTask = nil

        if result.state == .cancelled {
            phase = .cancelled
            return
        }
        if let root = result.root {
            navigator = DiskTreeNavigator(root: root)
            lastScannedAt = Date()
            persistCache(root: root)
        }
        phase = .completed
    }

    private func persistCache(root: DiskNode) {
        try? cache.save(root: root, rootURL: rootURL, scannedAt: lastScannedAt ?? Date())
    }

    private func shouldPublish() -> Bool {
        let now = Date()
        guard let lastPublishedAt else { self.lastPublishedAt = now; return true }
        if now.timeIntervalSince(lastPublishedAt) >= publishInterval {
            self.lastPublishedAt = now
            return true
        }
        return false
    }
}
