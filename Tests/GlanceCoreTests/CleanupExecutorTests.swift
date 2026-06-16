import XCTest
@testable import GlanceCore

final class CleanupExecutorTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testDeletesContentsButKeepsRoot() async throws {
        let root = try makeTempRoot()
        try writeFile(root.appendingPathComponent("a.dat"), byteCount: 100)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try writeFile(sub.appendingPathComponent("b.dat"), byteCount: 50)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path)) // 根目錄保留
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(remaining.isEmpty)                                  // 內容物清空

        let trash = try XCTUnwrap(result.categories.first { $0.id == .trash })
        XCTAssertEqual(trash.reclaimedBytes, 150)
        XCTAssertEqual(trash.deletedCount, 2)
        XCTAssertTrue(result.skippedPaths.isEmpty)
    }

    func testSymlinkChildIsSkippedAndTargetSurvives() async throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let sentinel = outside.appendingPathComponent("keep.dat")
        try writeFile(sentinel, byteCount: 42)
        let link = root.appendingPathComponent("evil-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try writeFile(root.appendingPathComponent("real.dat"), byteCount: 10)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        // 護欄:symlink 指向的外部 sentinel 必須存活,不被跟隨刪除。
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let trash = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(trash.deletedCount, 1)                 // 只刪 real.dat
        XCTAssertEqual(trash.reclaimedBytes, 10)
        XCTAssertEqual(result.skippedPaths.count, 1)          // symlink 進 skipped
        XCTAssertEqual(result.skippedPaths.first?.url, link)
    }

    func testEmptyCategoryYieldsZeroResult() async throws {
        let root = try makeTempRoot()
        let categories = [CleanupCategory(id: .userCaches, displayName: "使用者快取與日誌", roots: [root])]
        let result = await CleanupExecutor().run(categories: categories)

        let caches = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(caches.deletedCount, 0)
        XCTAssertEqual(caches.reclaimedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}
