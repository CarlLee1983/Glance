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

    /// 中間目錄為 symlink、且刪除目標尚未存在時,不可因 resolvingSymlinksInPath 不解析
    /// 不存在路徑而逃逸到 root 之外。
    func testRejectsIntermediateSymlinkEscape() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceTrashEscapeOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }

        let linkDir = root.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: outside)
        // 目標尾段 victim.dat 尚不存在,中間 linkdir 指向 root 之外。
        let target = linkDir.appendingPathComponent("victim.dat")

        XCTAssertFalse(DiskTrashSafety.isDeletable(target, withinRoot: root, protectedPaths: []))
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
