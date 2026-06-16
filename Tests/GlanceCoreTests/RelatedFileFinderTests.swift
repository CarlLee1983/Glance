import XCTest
@testable import GlanceCore

final class UninstallLocationsTests: XCTestCase {
    func testAppsDirectoriesAreApplicationsFolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let dirs = UninstallLocations.appsDirectories(home: home).map(\.path)
        XCTAssertEqual(dirs, ["/Applications", "/Users/tester/Applications"])
    }

    func testSupportDirectoriesCoverKnownLibrarySubfolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let dirs = UninstallLocations.supportDirectories(home: home).map(\.path)
        XCTAssertEqual(dirs, [
            "/Users/tester/Library/Application Support",
            "/Users/tester/Library/Caches",
            "/Users/tester/Library/Preferences",
            "/Users/tester/Library/Containers",
            "/Users/tester/Library/Group Containers",
            "/Users/tester/Library/Saved Application State",
            "/Users/tester/Library/Logs",
            "/Users/tester/Library/HTTPStorages",
            "/Users/tester/Library/WebKit",
            "/Users/tester/Library/Cookies",
            "/Users/tester/Library/LaunchAgents",
        ])
    }
}
