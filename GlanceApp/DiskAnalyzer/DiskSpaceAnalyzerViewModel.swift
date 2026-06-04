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
    @Published private(set) var largestFolders: [DiskSpaceItem] = []
    @Published private(set) var largestFiles: [DiskSpaceItem] = []
    @Published private(set) var skippedPaths: [DiskSpaceSkippedPath] = []

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastProgressPublishedAt: Date?
    private var lastProgressPublishedScannedCount = 0
    private let analyzer: DiskSpaceAnalyzer
    private let progressPublishInterval: TimeInterval = 0.2
    private let progressPublishCountInterval = 100

    init(analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer(maxResults: 50)) {
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
            let result = await analyzer.scan(rootURL: root) { [weak self] progress in
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
        largestFolders = []
        largestFiles = []
        skippedPaths = []
        lastProgressPublishedAt = nil
        lastProgressPublishedScannedCount = 0
    }

    private func apply(_ progress: DiskSpaceScanProgress, generation: Int) {
        guard generation == scanGeneration, shouldPublish(progress) else { return }

        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
        largestFolders = progress.largestFolders
        largestFiles = progress.largestFiles
    }

    private func apply(_ result: DiskSpaceScanResult, generation: Int) {
        guard generation == scanGeneration else { return }

        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        largestFolders = result.largestFolders
        largestFiles = result.largestFiles
        skippedPaths = result.skippedPaths
        phase = result.state == .cancelled ? .cancelled : .completed
        scanTask = nil
    }

    private func shouldPublish(_ progress: DiskSpaceScanProgress) -> Bool {
        let now = Date()
        guard let lastProgressPublishedAt else {
            recordPublishedProgress(progress, at: now)
            return true
        }

        let elapsed = now.timeIntervalSince(lastProgressPublishedAt)
        let scannedDelta = progress.scannedCount - lastProgressPublishedScannedCount
        let shouldPublish = elapsed >= progressPublishInterval || scannedDelta >= progressPublishCountInterval

        if shouldPublish {
            recordPublishedProgress(progress, at: now)
        }

        return shouldPublish
    }

    private func recordPublishedProgress(_ progress: DiskSpaceScanProgress, at date: Date) {
        lastProgressPublishedAt = date
        lastProgressPublishedScannedCount = progress.scannedCount
    }
}
