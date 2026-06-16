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
        XCTAssertEqual(result.skippedPaths.first?.url.lastPathComponent, "evil-link")
    }

    func testRoguePathOutsideRootIsBlockedBySafetyGuard() async throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let rogue = outside.appendingPathComponent("rogue.dat")
        try writeFile(rogue, byteCount: 77)

        // 模擬列舉回傳一個位於 root 之外的項目:護欄必須擋下,不得刪除。
        let stub = StubFileManager()
        stub.entriesForRoot[root] = [rogue]

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let result = await CleanupExecutor(fileManager: stub).run(categories: categories)

        XCTAssertTrue(FileManager.default.fileExists(atPath: rogue.path)) // 外部檔案存活
        let trash = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(trash.deletedCount, 0)
        XCTAssertEqual(trash.reclaimedBytes, 0)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.reason, "Blocked by safety guard")
    }

    func testDeleteFailureIsSkippedAndBatchContinues() async throws {
        let root = try makeTempRoot()
        try writeFile(root.appendingPathComponent("a.dat"), byteCount: 30)
        try writeFile(root.appendingPathComponent("b.dat"), byteCount: 40)

        let stub = StubFileManager()
        stub.throwOnRemove = true

        let categories = [CleanupCategory(id: .userCaches, displayName: "使用者快取與日誌", roots: [root])]
        let result = await CleanupExecutor(fileManager: stub).run(categories: categories)

        let caches = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(caches.deletedCount, 0)
        XCTAssertEqual(caches.reclaimedBytes, 0)
        XCTAssertEqual(result.skippedPaths.count, 2) // 兩個都失敗、都進 skipped,未中斷
        XCTAssertTrue(result.skippedPaths.allSatisfy { $0.reason.hasPrefix("Delete failed:") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.dat").path))
    }

    func testDeletesAcrossMultipleRoots() async throws {
        let rootA = try makeTempRoot()
        let rootB = try makeTempRoot()
        try writeFile(rootA.appendingPathComponent("x.dat"), byteCount: 11)
        try writeFile(rootB.appendingPathComponent("y.dat"), byteCount: 22)

        let categories = [CleanupCategory(id: .devCaches, displayName: "開發工具快取", roots: [rootA, rootB])]
        let result = await CleanupExecutor().run(categories: categories)

        let dev = try XCTUnwrap(result.categories.first)
        XCTAssertEqual(dev.deletedCount, 2)
        XCTAssertEqual(dev.reclaimedBytes, 33)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: rootA.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: rootB.path).isEmpty)
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

private final class StubFileManager: FileManager {
    var entriesForRoot: [URL: [URL]] = [:]
    var throwOnRemove = false

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if let entries = entriesForRoot[url] { return entries }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }

    override func removeItem(at url: URL) throws {
        if throwOnRemove { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}
