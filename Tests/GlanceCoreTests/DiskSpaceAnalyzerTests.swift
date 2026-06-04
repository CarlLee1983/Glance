import XCTest
@testable import GlanceCore

final class DiskSpaceAnalyzerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRanksLargestFilesDescending() async throws {
        let root = try makeTemporaryRoot()
        try writeFile(root.appendingPathComponent("small.bin"), byteCount: 10)
        try writeFile(root.appendingPathComponent("large.bin"), byteCount: 40)
        try writeFile(root.appendingPathComponent("medium.bin"), byteCount: 20)

        let result = await DiskSpaceAnalyzer(maxResults: 2).scan(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.largestFiles.map(\.name), ["large.bin", "medium.bin"])
        XCTAssertEqual(result.largestFiles.map(\.sizeBytes), [40, 20])
    }

    func testFolderSizesIncludeNestedChildren() async throws {
        let root = try makeTemporaryRoot()
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try writeFile(parent.appendingPathComponent("one.dat"), byteCount: 15)
        try writeFile(child.appendingPathComponent("two.dat"), byteCount: 25)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        let parentItem = try XCTUnwrap(result.largestFolders.first { $0.url == parent })
        let childItem = try XCTUnwrap(result.largestFolders.first { $0.url == child })
        XCTAssertEqual(parentItem.sizeBytes, 40)
        XCTAssertEqual(childItem.sizeBytes, 25)
    }

    func testIncludesHiddenDirectories() async throws {
        let root = try makeTemporaryRoot()
        let hidden = root.appendingPathComponent(".cache", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeFile(hidden.appendingPathComponent("cache.dat"), byteCount: 33)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertTrue(result.largestFolders.contains { $0.url == hidden && $0.sizeBytes == 33 })
        XCTAssertTrue(result.largestFiles.contains { $0.name == "cache.dat" && $0.sizeBytes == 33 })
    }

    func testDoesNotFollowSymlinks() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        try writeFile(outside.appendingPathComponent("outside.dat"), byteCount: 99)
        let symlink = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertFalse(result.largestFiles.contains { $0.name == "outside.dat" })
        XCTAssertFalse(result.largestFolders.contains { $0.url.path.contains(outside.path) })
    }

    func testMissingRootIsSkippedWithoutFailingScan() async throws {
        let root = try makeTemporaryRoot()
        try FileManager.default.removeItem(at: root)

        let result = await DiskSpaceAnalyzer(maxResults: 10).scan(rootURL: root)

        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(result.scannedCount, 0)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, root)
    }

    func testCancellationReturnsCancelledState() async throws {
        let root = try makeTemporaryRoot()
        for index in 0..<200 {
            try writeFile(root.appendingPathComponent("file-\(index).dat"), byteCount: 1)
        }

        let analyzer = DiskSpaceAnalyzer(maxResults: 10)
        let task = Task {
            await analyzer.scan(rootURL: root) { _ in
                Task.cancel()
            }
        }
        let result = await task.value

        XCTAssertEqual(result.state, .cancelled)
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
