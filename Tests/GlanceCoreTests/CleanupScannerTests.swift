import XCTest
@testable import GlanceCore

final class CleanupSizingTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testSizeSumsNestedFiles() throws {
        let root = try makeTempRoot()
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("a/one.dat"), byteCount: 10)
        try writeFile(nested.appendingPathComponent("two.dat"), byteCount: 25)

        XCTAssertEqual(CleanupSizing.size(of: root.appendingPathComponent("a"), fileManager: .default), 35)
    }

    func testSizeIgnoresSymbolicLinks() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeFile(outside.appendingPathComponent("big.dat"), byteCount: 999)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertEqual(CleanupSizing.size(of: link, fileManager: .default), 0)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupSizingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}

final class CleanupScannerTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testScanReportsBytesAndItemCountPerCategory() async throws {
        let trashRoot = try makeTempRoot()
        try writeFile(trashRoot.appendingPathComponent("junk1.dat"), byteCount: 100)
        try writeFile(trashRoot.appendingPathComponent("junk2.dat"), byteCount: 50)

        let cacheRoot = try makeTempRoot()
        let nested = cacheRoot.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(nested.appendingPathComponent("c.dat"), byteCount: 30)

        let categories = [
            CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [trashRoot]),
            CleanupCategory(id: .userCaches, displayName: "使用者快取與日誌", roots: [cacheRoot]),
        ]

        let results = await CleanupScanner().scan(categories: categories)

        let trash = try XCTUnwrap(results.first { $0.id == .trash })
        XCTAssertEqual(trash.reclaimableBytes, 150)
        XCTAssertEqual(trash.itemCount, 2)

        let caches = try XCTUnwrap(results.first { $0.id == .userCaches })
        XCTAssertEqual(caches.reclaimableBytes, 30)
        XCTAssertEqual(caches.itemCount, 1) // "app" 目錄算一項
    }

    func testScanSkipsSymbolicLinks() async throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeFile(outside.appendingPathComponent("big.dat"), byteCount: 500)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try writeFile(root.appendingPathComponent("real.dat"), byteCount: 20)

        let categories = [CleanupCategory(id: .trash, displayName: "垃圾桶", roots: [root])]
        let results = await CleanupScanner().scan(categories: categories)

        let trash = try XCTUnwrap(results.first)
        XCTAssertEqual(trash.reclaimableBytes, 20) // 不含 symlink 指向的 500
        XCTAssertEqual(trash.itemCount, 1)         // symlink 不計入
    }

    func testMissingRootContributesZero() async throws {
        let root = try makeTempRoot()
        try FileManager.default.removeItem(at: root) // 不存在

        let categories = [CleanupCategory(id: .devCaches, displayName: "開發工具快取", roots: [root])]
        let results = await CleanupScanner().scan(categories: categories)

        let dev = try XCTUnwrap(results.first)
        XCTAssertEqual(dev.reclaimableBytes, 0)
        XCTAssertEqual(dev.itemCount, 0)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x7A, count: byteCount).write(to: url)
    }
}
