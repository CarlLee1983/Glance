import XCTest
@testable import GlanceCore

final class DiskTrashServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskTrashServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTrashesAllowedItemsAndCountsBytes() {
        let trashed = TrashRecorder()
        let service = DiskTrashService(trash: { trashed.record($0) })
        let item = DiskTrashRequestItem(url: root.appendingPathComponent("a.dat"), sizeBytes: 100)

        let result = service.run(items: [item], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 1)
        XCTAssertEqual(result.freedBytes, 100)
        XCTAssertTrue(result.skippedPaths.isEmpty)
        XCTAssertEqual(trashed.urls, [item.url])
    }

    func testSkipsBlockedItemsWithoutTrashing() {
        let trashed = TrashRecorder()
        let service = DiskTrashService(trash: { trashed.record($0) })
        // root 本身會被護欄擋下
        let item = DiskTrashRequestItem(url: root, sizeBytes: 999)

        let result = service.run(items: [item], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 0)
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertTrue(trashed.urls.isEmpty)
    }

    func testContinuesAfterTrashFailure() {
        struct TrashError: Error {}
        let service = DiskTrashService(trash: { url in
            if url.lastPathComponent == "boom.dat" { throw TrashError() }
        })
        let ok = DiskTrashRequestItem(url: root.appendingPathComponent("ok.dat"), sizeBytes: 10)
        let boom = DiskTrashRequestItem(url: root.appendingPathComponent("boom.dat"), sizeBytes: 20)

        let result = service.run(items: [boom, ok], withinRoot: root, protectedPaths: [])

        XCTAssertEqual(result.trashedCount, 1)
        XCTAssertEqual(result.freedBytes, 10)
        XCTAssertEqual(result.skippedPaths.count, 1)
        XCTAssertEqual(result.skippedPaths.first?.url, boom.url)
    }
}

private final class TrashRecorder: @unchecked Sendable {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
