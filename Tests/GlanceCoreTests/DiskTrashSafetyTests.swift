import XCTest
@testable import GlanceCore

final class DiskTrashSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDiskTrashSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("deep/nested", isDirectory: true), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAcceptsDeepDescendant() {
        let target = root.appendingPathComponent("deep/nested")
        XCTAssertTrue(DiskTrashSafety.isDeletable(target, withinRoot: root, protectedPaths: []))
    }

    func testRejectsRootItself() {
        XCTAssertFalse(DiskTrashSafety.isDeletable(root, withinRoot: root, protectedPaths: []))
    }

    func testRejectsPathOutsideRoot() {
        let outside = root.deletingLastPathComponent().appendingPathComponent("sibling")
        XCTAssertFalse(DiskTrashSafety.isDeletable(outside, withinRoot: root, protectedPaths: []))
    }

    func testRejectsSymlinkLeaf() throws {
        let realDir = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realDir)
        XCTAssertFalse(DiskTrashSafety.isDeletable(link, withinRoot: root, protectedPaths: []))
    }

    func testRejectsProtectedPath() {
        let protectedDir = root.appendingPathComponent("deep")
        XCTAssertFalse(DiskTrashSafety.isDeletable(protectedDir, withinRoot: root, protectedPaths: [protectedDir]))
        // 但其子項仍可刪
        XCTAssertTrue(DiskTrashSafety.isDeletable(protectedDir.appendingPathComponent("nested"), withinRoot: root, protectedPaths: [protectedDir]))
    }

    func testRejectsShallowRoot() {
        XCTAssertFalse(DiskTrashSafety.isDeletable(URL(fileURLWithPath: "/etc"), withinRoot: URL(fileURLWithPath: "/"), protectedPaths: []))
    }
}
