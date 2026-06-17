import XCTest
@testable import GlanceCore

final class DiskSpaceAnalyzerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRanksChildrenBySizeDescending() async throws {
        let root = try makeTemporaryRoot()
        try writeFile(root.appendingPathComponent("small.bin"), byteCount: 10)
        try writeFile(root.appendingPathComponent("large.bin"), byteCount: 40)
        try writeFile(root.appendingPathComponent("medium.bin"), byteCount: 20)

        let result = await DiskSpaceAnalyzer().scanTree(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        let rootNode = try XCTUnwrap(result.root)
        XCTAssertEqual(rootNode.children.map(\.name), ["large.bin", "medium.bin", "small.bin"])
        XCTAssertEqual(rootNode.children.map(\.sizeBytes), [40, 20, 10])
        XCTAssertEqual(rootNode.sizeBytes, 70)
    }

    func testFolderSizesIncludeNestedChildren() async throws {
        let root = try makeTemporaryRoot()
        let parentDir = root.appendingPathComponent("parent", isDirectory: true)
        let childDir = parentDir.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        try writeFile(parentDir.appendingPathComponent("one.dat"), byteCount: 15)
        try writeFile(childDir.appendingPathComponent("two.dat"), byteCount: 25)

        let scanResult = await DiskSpaceAnalyzer().scanTree(rootURL: root)
        let rootNode = try XCTUnwrap(scanResult.root)
        let parentNode = try XCTUnwrap(child(named: "parent", in: rootNode))
        let childNode = try XCTUnwrap(child(named: "child", in: parentNode))
        XCTAssertEqual(parentNode.sizeBytes, 40)
        XCTAssertEqual(childNode.sizeBytes, 25)
    }

    func testIncludesHiddenDirectories() async throws {
        let root = try makeTemporaryRoot()
        let hidden = root.appendingPathComponent(".cache", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(hidden.appendingPathComponent("cache.dat"), byteCount: 33)

        let scanResult = await DiskSpaceAnalyzer().scanTree(rootURL: root)
        let rootNode = try XCTUnwrap(scanResult.root)
        let hiddenNode = try XCTUnwrap(child(named: ".cache", in: rootNode))
        XCTAssertEqual(hiddenNode.sizeBytes, 33)
    }

    func testDoesNotFollowSymlinks() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        try writeFile(outside.appendingPathComponent("outside.dat"), byteCount: 99)
        let symlink = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let scanResult = await DiskSpaceAnalyzer().scanTree(rootURL: root)
        let rootNode = try XCTUnwrap(scanResult.root)
        XCTAssertNil(child(named: "outside-link", in: rootNode))
    }

    func testMissingRootIsSkippedWithoutFailingScan() async throws {
        let root = try makeTemporaryRoot()
        try FileManager.default.removeItem(at: root)

        let result = await DiskSpaceAnalyzer().scanTree(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertNil(result.root)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, root)
    }

    func testAggregatesSmallChildrenBeyondKeepTop() async throws {
        let root = try makeTemporaryRoot()
        try writeFile(root.appendingPathComponent("a.dat"), byteCount: 50)
        try writeFile(root.appendingPathComponent("b.dat"), byteCount: 40)
        try writeFile(root.appendingPathComponent("c.dat"), byteCount: 30)
        try writeFile(root.appendingPathComponent("d.dat"), byteCount: 20)
        try writeFile(root.appendingPathComponent("e.dat"), byteCount: 10)

        let scanResult = await DiskSpaceAnalyzer(keepTopPerFolder: 3).scanTree(rootURL: root)
        let rootNode = try XCTUnwrap(scanResult.root)

        XCTAssertEqual(rootNode.children.count, 4) // 3 個別 + 1 聚合
        let aggregate = try XCTUnwrap(rootNode.children.last)
        XCTAssertTrue(aggregate.isAggregate)
        XCTAssertEqual(aggregate.aggregateCount, 2)
        XCTAssertEqual(aggregate.sizeBytes, 30) // 20 + 10
        XCTAssertEqual(rootNode.sizeBytes, 150)
    }

    func testCancellationReturnsCancelledState() async throws {
        let root = try makeTemporaryRoot()
        for index in 0..<400 {
            try writeFile(root.appendingPathComponent("file-\(index).dat"), byteCount: 1)
        }

        let analyzer = DiskSpaceAnalyzer()
        let cancellationGate = CancellationGate()
        let scanTask = Task {
            await analyzer.scanTree(rootURL: root) { progress in
                if progress.scannedCount > 0 { await cancellationGate.pauseUntilReleased() }
            }
        }

        await cancellationGate.waitForPause()
        scanTask.cancel()
        await cancellationGate.release()
        let result = await scanTask.value

        XCTAssertEqual(result.state, .cancelled)
    }

    // MARK: - Helpers

    private func child(named name: String, in node: DiskNode) -> DiskNode? {
        node.children.first { $0.name == name }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskSpaceAnalyzerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        let data = Data(repeating: 0x7A, count: byteCount)
        try data.write(to: url)
    }
}

private actor CancellationGate {
    private var isPaused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForPause() async {
        if isPaused { return }
        await withCheckedContinuation { continuation in pauseContinuation = continuation }
    }

    func pauseUntilReleased() async {
        guard !isPaused else { return }
        isPaused = true
        pauseContinuation?.resume()
        pauseContinuation = nil
        await withCheckedContinuation { continuation in releaseContinuation = continuation }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
