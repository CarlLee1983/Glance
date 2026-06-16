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
