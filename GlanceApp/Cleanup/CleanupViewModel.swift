import Combine
import Foundation
import GlanceCore

@MainActor
final class CleanupViewModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case selecting
        case confirming
        case running
        case done
    }

    struct Row: Identifiable {
        let category: CleanupCategory
        let result: CleanupCategoryResult
        var isSelected: Bool
        var id: CleanupCategoryID { category.id }
    }

    @Published private(set) var phase: Phase = .scanning
    @Published private(set) var rows: [Row] = []
    @Published private(set) var currentPath: String?
    @Published private(set) var runResult: CleanupRunResult?

    private let categories: [CleanupCategory]
    private let scanner: CleanupScanner
    private let executor: CleanupExecutor
    private var scanTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(
        categories: [CleanupCategory] = CleanupCategory.defaults(),
        scanner: CleanupScanner = CleanupScanner(),
        executor: CleanupExecutor = CleanupExecutor()
    ) {
        self.categories = categories
        self.scanner = scanner
        self.executor = executor
    }

    deinit {
        scanTask?.cancel()
        runTask?.cancel()
    }

    // MARK: Derived

    var selectedRows: [Row] { rows.filter(\.isSelected) }
    var selectedCategories: [CleanupCategory] { selectedRows.map(\.category) }
    var selectedCount: Int { selectedRows.count }
    var selectedBytes: UInt64 { selectedRows.reduce(0) { $0 + $1.result.reclaimableBytes } }
    var hasSelection: Bool { !selectedRows.isEmpty }

    // MARK: Actions

    func startScan() {
        scanTask?.cancel()
        phase = .scanning
        rows = []
        currentPath = nil
        let categories = categories
        scanTask = Task { [weak self, scanner] in
            let results = await scanner.scan(categories: categories) { [weak self] progress in
                await self?.applyScanProgress(progress)
            }
            await self?.applyScanResults(results)
        }
    }

    func toggle(_ id: CleanupCategoryID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isSelected.toggle()
    }

    func requestConfirmation() {
        guard hasSelection else { return }
        phase = .confirming
    }

    func cancelConfirmation() {
        phase = .selecting
    }

    func confirmDelete() {
        runTask?.cancel()
        phase = .running
        currentPath = nil
        let targets = selectedCategories
        runTask = Task { [weak self, executor] in
            let result = await executor.run(categories: targets) { [weak self] progress in
                await self?.applyRunProgress(progress)
            }
            await self?.applyRunResult(result)
        }
    }

    // MARK: Apply (MainActor)

    private func applyScanProgress(_ progress: CleanupScanProgress) {
        guard phase == .scanning else { return }
        currentPath = progress.currentPath
    }

    private func applyScanResults(_ results: [CleanupCategoryResult]) {
        rows = categories.compactMap { category in
            guard let result = results.first(where: { $0.id == category.id }) else { return nil }
            // 預設勾選有可回收項目的類別。
            return Row(category: category, result: result, isSelected: result.itemCount > 0)
        }
        currentPath = nil
        phase = .selecting
        scanTask = nil
    }

    private func applyRunProgress(_ progress: CleanupRunProgress) {
        guard phase == .running else { return }
        currentPath = progress.currentPath
    }

    private func applyRunResult(_ result: CleanupRunResult) {
        runResult = result
        currentPath = nil
        phase = .done
        runTask = nil
    }
}
