import Combine
import Foundation
import GlanceCore

@MainActor
final class DiskSpaceAnalyzerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case completed
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var scannedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var currentPath: String?
    @Published private(set) var rootNode: DiskNode?
    @Published private(set) var skippedPaths: [DiskSpaceSkippedPath] = []

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private let analyzer: DiskSpaceAnalyzer

    init(analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer()) {
        self.analyzer = analyzer
    }

    deinit {
        scanTask?.cancel()
    }

    var isScanning: Bool {
        phase == .scanning
    }

    var statusText: String {
        switch phase {
        case .idle:
            return "Ready to scan your home directory"
        case .scanning:
            return "Scanning..."
        case .completed:
            return "Scan complete"
        case .cancelled:
            return "Scan cancelled"
        }
    }

    func startScan() {
        scanTask?.cancel()
        scanGeneration += 1
        resetForScan()

        let root = rootURL
        let generation = scanGeneration
        scanTask = Task { [weak self, analyzer] in
            let result = await analyzer.scanTree(rootURL: root) { [weak self] progress in
                await self?.apply(progress, generation: generation)
            }
            await self?.apply(result, generation: generation)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func resetForScan() {
        phase = .scanning
        scannedCount = 0
        skippedCount = 0
        currentPath = nil
        rootNode = nil
        skippedPaths = []
    }

    private func apply(_ progress: DiskTreeScanProgress, generation: Int) {
        guard generation == scanGeneration else { return }
        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
    }

    private func apply(_ result: DiskTreeScanResult, generation: Int) {
        guard generation == scanGeneration else { return }
        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        rootNode = result.root
        skippedPaths = result.skippedPaths
        phase = result.state == .cancelled ? .cancelled : .completed
        scanTask = nil
    }
}
