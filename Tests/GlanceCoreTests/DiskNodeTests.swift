import XCTest
@testable import GlanceCore

final class DiskNodeTests: XCTestCase {
    func testDefaultNameDerivesFromURL() {
        let node = DiskNode(
            url: URL(fileURLWithPath: "/tmp/foo/bar.txt"),
            kind: .file, sizeBytes: 10, modifiedAt: nil
        )
        XCTAssertEqual(node.name, "bar.txt")
        XCTAssertEqual(node.id, "/tmp/foo/bar.txt")
        XCTAssertFalse(node.isAggregate)
    }

    func testCodableRoundTripPreservesTree() throws {
        let child = DiskNode(url: URL(fileURLWithPath: "/r/a"), kind: .file, sizeBytes: 5, modifiedAt: nil)
        let root = DiskNode(
            url: URL(fileURLWithPath: "/r"), kind: .folder, sizeBytes: 5,
            modifiedAt: Date(timeIntervalSince1970: 1000), children: [child]
        )
        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(DiskNode.self, from: data)
        XCTAssertEqual(decoded, root)
    }
}
