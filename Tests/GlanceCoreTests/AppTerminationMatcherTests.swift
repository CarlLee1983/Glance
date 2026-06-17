import XCTest
@testable import GlanceCore

final class AppTerminationMatcherTests: XCTestCase {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testReturnsMatchingRunningApp() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertEqual(result, running)
    }

    func testExcludesCurrentApp() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: true)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsEmptyWhenNoMatch() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Bar.app"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: running)
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsAllInstancesWithSameBundle() {
        let a = RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)
        let b = RunningAppRef(bundleURL: url("/Applications/Foo.app"), isCurrentApp: false)
        let result = AppTerminationMatcher.matches(target: url("/Applications/Foo.app"), running: [a, b])
        XCTAssertEqual(result.count, 2)
    }

    func testMatchesDespitePathRepresentationDifferences() {
        let running = [RunningAppRef(bundleURL: url("/Applications/Foo.app/"), isCurrentApp: false)]
        let result = AppTerminationMatcher.matches(target: url("/Applications/./Foo.app"), running: running)
        XCTAssertEqual(result.count, 1)
    }
}
