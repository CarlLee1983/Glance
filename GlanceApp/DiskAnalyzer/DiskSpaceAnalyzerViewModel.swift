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
    private let analyzer: DiskSpaceAnalyzer

    init(analyzer: DiskSpaceAnalyzer = DiskSpaceAnalyzer(maxResults: 50)) {
        self.analyzer = analyzer
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
        resetForScan()

        let root = rootURL
        scanTask = Task { [analyzer] in
            let result = await analyzer.scan(rootURL: root) { [weak self] progress in
                await self?.apply(progress)
            }
            await apply(result)
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
    }

    private func apply(_ progress: DiskSpaceScanProgress) {
        scannedCount = progress.scannedCount
        skippedCount = progress.skippedCount
        currentPath = progress.currentPath
        largestFolders = progress.largestFolders
        largestFiles = progress.largestFiles
    }

    private func apply(_ result: DiskSpaceScanResult) {
        scannedCount = result.scannedCount
        skippedCount = result.skippedPaths.count
        currentPath = nil
        largestFolders = result.largestFolders
        largestFiles = result.largestFiles
        skippedPaths = result.skippedPaths
        phase = result.state == .cancelled ? .cancelled : .completed
        scanTask = nil
    }
}
