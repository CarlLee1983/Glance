import XCTest
@testable import GlanceCore

final class CleanupCategoryTests: XCTestCase {
    func testDefaultsProvideThreeCategoriesWithExpectedRoots() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let categories = CleanupCategory.defaults(home: home)

        XCTAssertEqual(categories.map(\.id), [.trash, .userCaches, .devCaches])

        let trash = categories.first { $0.id == .trash }
        XCTAssertEqual(trash?.roots.map(\.path), ["/Users/tester/.Trash"])

        let userCaches = categories.first { $0.id == .userCaches }
        XCTAssertEqual(userCaches?.roots.map(\.path),
                       ["/Users/tester/Library/Caches", "/Users/tester/Library/Logs"])

        let devCaches = categories.first { $0.id == .devCaches }
        XCTAssertEqual(devCaches?.roots.map(\.path),
                       ["/Users/tester/Library/Developer/Xcode/DerivedData",
                        "/Users/tester/.npm",
                        "/Users/tester/.cache"])
    }
}

final class CleanupSafetyTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testChildUnderRootIsDeletable() throws {
        let root = try makeTempRoot()
        let child = root.appendingPathComponent("cache.dat")
        XCTAssertTrue(CleanupSafety.isDeletable(child, within: [root]))
    }

    func testRootItselfIsNotDeletable() throws {
        let root = try makeTempRoot()
        XCTAssertFalse(CleanupSafety.isDeletable(root, within: [root]))
    }

    func testPathOutsideRootIsNotDeletable() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let stray = outside.appendingPathComponent("doc.txt")
        XCTAssertFalse(CleanupSafety.isDeletable(stray, within: [root]))
    }

    func testSiblingWithSharedPrefixIsNotDeletable() throws {
        // root 為 ".../Caches";".../Caches2/x" 不該被誤判為在 root 底下。
        let base = try makeTempRoot()
        let root = base.appendingPathComponent("Caches", isDirectory: true)
        let sibling = base.appendingPathComponent("Caches2/x")
        XCTAssertFalse(CleanupSafety.isDeletable(sibling, within: [root]))
    }

    func testParentTraversalIsNotDeletable() throws {
        let root = try makeTempRoot()
        let escaping = root.appendingPathComponent("../escape.dat")
        XCTAssertFalse(CleanupSafety.isDeletable(escaping, within: [root]))
    }

    func testSymbolicLinkIsNotDeletable() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(CleanupSafety.isDeletable(link, within: [root]))
    }

    func testIntermediateSymlinkEscapeIsNotDeletable() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        // link/secret.dat 經解析後實為 outside/secret.dat,落在 root 之外。
        let escaping = link.appendingPathComponent("secret.dat")
        XCTAssertFalse(CleanupSafety.isDeletable(escaping, within: [root]))
    }

    func testEmptyRootsIsNotDeletable() throws {
        let root = try makeTempRoot()
        let child = root.appendingPathComponent("cache.dat")
        XCTAssertFalse(CleanupSafety.isDeletable(child, within: []))
    }

    func testMatchesAgainstSecondRoot() throws {
        let first = try makeTempRoot()
        let second = try makeTempRoot()
        let child = second.appendingPathComponent("cache.dat")
        XCTAssertTrue(CleanupSafety.isDeletable(child, within: [first, second]))
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceCleanupSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }
}
