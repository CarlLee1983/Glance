import XCTest
@testable import GlanceCore

final class CleanupCategoryTests: XCTestCase {
    func testDefaultsProvideThreeCategoriesWithExpectedRoots() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let categories = CleanupCategory.defaults(home: home)

        XCTAssertEqual(categories.map(\.id), [.trash, .userCaches, .devCaches])

        let trash = try? XCTUnwrap(categories.first { $0.id == .trash })
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
