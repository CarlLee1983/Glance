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

final class RelatedFileFinderTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceRelatedFinder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    private func touch(_ url: URL, bytes: Int = 5) throws {
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    func testMatchesExactAndDotPrefixOnly() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("com.foo.Bar"))            // 完全一致
        try touch(support.appendingPathComponent("com.foo.Bar.plist"))      // 點前綴
        try touch(support.appendingPathComponent("com.foo.Bar.savedState")) // 點前綴
        try touch(support.appendingPathComponent("com.foo.BarHelper"))      // 無點延伸 → 不命中
        try touch(support.appendingPathComponent("com.other.App.plist"))    // 別 App → 不命中

        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        let names = Set(found.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.foo.Bar", "com.foo.Bar.plist", "com.foo.Bar.savedState"])
    }

    func testEmptyBundleIDReturnsNothing() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("anything"))
        let found = await RelatedFileFinder().find(bundleID: "", supportDirectories: [support])
        XCTAssertTrue(found.isEmpty)
    }

    func testSymlinkMatchIsSkipped() async throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let target = outside.appendingPathComponent("real")
        try touch(target)
        let link = support.appendingPathComponent("com.foo.Bar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        XCTAssertTrue(found.isEmpty)
    }

    func testComputesSizeForMatchedFile() async throws {
        let support = try makeTempDir()
        try touch(support.appendingPathComponent("com.foo.Bar.plist"), bytes: 42)
        let found = await RelatedFileFinder().find(bundleID: "com.foo.Bar", supportDirectories: [support])
        XCTAssertEqual(found.first?.sizeBytes, 42)
    }
}
