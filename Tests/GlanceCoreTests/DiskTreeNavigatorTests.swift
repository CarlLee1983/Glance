import XCTest
@testable import GlanceCore

final class DiskTreeNavigatorTests: XCTestCase {
    /// 樹:root(/r, 100) ├ big(/r/big, 70) │ └ leaf(/r/big/leaf.dat, 70)  └ small(/r/small.dat, 30)
    private func makeTree() -> DiskNode {
        let leaf = DiskNode(url: URL(fileURLWithPath: "/r/big/leaf.dat"), kind: .file, sizeBytes: 70, modifiedAt: nil)
        let big = DiskNode(url: URL(fileURLWithPath: "/r/big"), kind: .folder, sizeBytes: 70, modifiedAt: nil, children: [leaf])
        let small = DiskNode(url: URL(fileURLWithPath: "/r/small.dat"), kind: .file, sizeBytes: 30, modifiedAt: nil)
        return DiskNode(url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 100, modifiedAt: nil, children: [big, small])
    }

    func testDrillUpdatesCurrentNodeAndBreadcrumb() {
        var nav = DiskTreeNavigator(root: makeTree())
        let big = nav.currentNode.children.first { $0.name == "big" }!
        nav.drill(into: big)
        XCTAssertEqual(nav.currentNode.id, "/r/big")
        XCTAssertEqual(nav.breadcrumb.map(\.name), ["r", "big"])
        XCTAssertTrue(nav.canGoUp)
    }

    func testDrillIgnoresNonFolder() {
        var nav = DiskTreeNavigator(root: makeTree())
        let small = nav.currentNode.children.first { $0.name == "small.dat" }!
        nav.drill(into: small)
        XCTAssertEqual(nav.currentNode.id, "/r")
    }

    func testGoUpAndJumpToDepth() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.goUp()
        XCTAssertEqual(nav.currentNode.id, "/r")
        XCTAssertFalse(nav.canGoUp)

        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.jump(toDepth: 0)
        XCTAssertEqual(nav.currentNode.id, "/r")
    }

    func testRemoveRecomputesAncestorSizes() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.remove(ids: ["/r/small.dat"])
        XCTAssertEqual(nav.root.sizeBytes, 70)
        XCTAssertNil(nav.currentNode.children.first { $0.name == "small.dat" })
    }

    func testRemoveNodeOnPathClampsPath() {
        var nav = DiskTreeNavigator(root: makeTree())
        nav.drill(into: nav.currentNode.children.first { $0.name == "big" }!)
        nav.remove(ids: ["/r/big"])
        XCTAssertEqual(nav.currentNode.id, "/r") // path 被裁回有效層
        XCTAssertEqual(nav.root.sizeBytes, 30)
    }
}
