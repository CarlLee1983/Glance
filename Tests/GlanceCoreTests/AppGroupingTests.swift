import XCTest
@testable import GlanceCore

final class AppGroupingTests: XCTestCase {
    func testChromeHelperNestedPathGroupsUnderApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "Google Chrome Helper (Renderer)")
        XCTAssertEqual(id.appName, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(id.bundleURL?.path, "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app")
        XCTAssertEqual(id.groupKey, id.bundleURL?.path)
    }

    func testPlainAppGroupsUnderItsBundle() {
        let path = "/Applications/Foo.app/Contents/MacOS/Foo"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "Foo")
        XCTAssertEqual(id.appName, "Foo")
        XCTAssertEqual(id.bundleURL?.path, "/Applications/Foo.app")
        XCTAssertEqual(id.groupKey, "/Applications/Foo.app")
    }

    func testDaemonWithoutAppFallsBackToProcessName() {
        let path = "/usr/sbin/cfprefsd"
        let id = AppGrouping.identity(executablePath: path, fallbackName: "cfprefsd")
        XCTAssertEqual(id.appName, "cfprefsd")
        XCTAssertNil(id.bundleURL)
        XCTAssertEqual(id.groupKey, "cfprefsd")
    }

    func testNilOrEmptyPathFallsBackToProcessName() {
        let idNil = AppGrouping.identity(executablePath: nil, fallbackName: "kernel_task")
        XCTAssertEqual(idNil.appName, "kernel_task")
        XCTAssertNil(idNil.bundleURL)
        XCTAssertEqual(idNil.groupKey, "kernel_task")

        let idEmpty = AppGrouping.identity(executablePath: "", fallbackName: "kernel_task")
        XCTAssertEqual(idEmpty.appName, "kernel_task")
        XCTAssertNil(idEmpty.bundleURL)
    }
}
