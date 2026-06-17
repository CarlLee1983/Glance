import XCTest
@testable import GlanceCore

final class DiskScanCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskScanCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleRoot() -> DiskNode {
        let child = DiskNode(url: URL(fileURLWithPath: "/r/a.dat"), kind: .file, sizeBytes: 5, modifiedAt: nil)
        return DiskNode(url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 5, modifiedAt: nil, children: [child])
    }

    func testSaveThenLoadRoundTrips() throws {
        let cache = DiskScanCache(directory: directory)
        let root = sampleRoot()
        let rootURL = URL(fileURLWithPath: "/r")
        let when = Date(timeIntervalSince1970: 1700)

        try cache.save(root: root, rootURL: rootURL, scannedAt: when)
        let loaded = try XCTUnwrap(cache.load(rootURL: rootURL))

        XCTAssertEqual(loaded.root, root)
        XCTAssertEqual(loaded.scannedAt, when)
        XCTAssertEqual(loaded.retainedDepth, 2)
    }

    func testLoadRejectsLegacyEntryWithoutRetainedDepth() throws {
        let cache = DiskScanCache(directory: directory)
        let rootURL = URL(fileURLWithPath: "/r")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "rootPath": "/r",
          "scannedAt": 1700,
          "root": {
            "url": "file:///r",
            "name": "r",
            "kind": "folder",
            "sizeBytes": 0,
            "modifiedAt": null,
            "children": [],
            "isAggregate": false,
            "aggregateCount": 0
          }
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: cache.fileURLForTesting(rootURL: rootURL))

        XCTAssertNil(cache.load(rootURL: rootURL))
    }

    func testLoadIgnoresLegacyUnversionedCacheFile() throws {
        let cache = DiskScanCache(directory: directory)
        let rootURL = URL(fileURLWithPath: "/r")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x7A, count: 1024).write(to: cache.legacyFileURLForTesting(rootURL: rootURL))

        XCTAssertNil(cache.load(rootURL: rootURL))
    }

    func testLoadMissingReturnsNil() {
        let cache = DiskScanCache(directory: directory)
        XCTAssertNil(cache.load(rootURL: URL(fileURLWithPath: "/does/not/exist")))
    }

    func testClearRemovesEntry() throws {
        let cache = DiskScanCache(directory: directory)
        let rootURL = URL(fileURLWithPath: "/r")
        try cache.save(root: sampleRoot(), rootURL: rootURL, scannedAt: Date(timeIntervalSince1970: 1))
        cache.clear(rootURL: rootURL)
        XCTAssertNil(cache.load(rootURL: rootURL))
    }

    func testDistinctRootsDoNotCollide() throws {
        let cache = DiskScanCache(directory: directory)
        let a = URL(fileURLWithPath: "/alpha")
        let b = URL(fileURLWithPath: "/beta")
        try cache.save(root: DiskNode(url: a, kind: .folder, sizeBytes: 1, modifiedAt: nil), rootURL: a, scannedAt: Date(timeIntervalSince1970: 1))
        try cache.save(root: DiskNode(url: b, kind: .folder, sizeBytes: 2, modifiedAt: nil), rootURL: b, scannedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(cache.load(rootURL: a)?.root.sizeBytes, 1)
        XCTAssertEqual(cache.load(rootURL: b)?.root.sizeBytes, 2)
    }
}
