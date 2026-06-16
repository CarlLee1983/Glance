import XCTest
@testable import GlanceCore

final class AppDiscoveryTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceAppDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    /// 在 appsDir 造一個假 .app:Contents/Info.plist + 一個內容檔(撐出大小)。
    @discardableResult
    private func makeApp(
        in appsDir: URL, fileName: String, bundleID: String?, name: String?, payload: Int = 10
    ) throws -> URL {
        let app = appsDir.appendingPathComponent(fileName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var dict: [String: Any] = [:]
        if let bundleID { dict["CFBundleIdentifier"] = bundleID }
        if let name { dict["CFBundleName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0, count: payload).write(to: contents.appendingPathComponent("blob.bin"))
        return app
    }

    func testDiscoversAppWithBundleIDNameAndSize() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "Foo.app", bundleID: "com.foo.Bar", name: "Foo App", payload: 100)

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertEqual(result.count, 1)
        let app = try XCTUnwrap(result.first)
        XCTAssertEqual(app.bundleID, "com.foo.Bar")
        XCTAssertEqual(app.name, "Foo App")
        XCTAssertGreaterThanOrEqual(app.sizeBytes, 100)
    }

    func testAppWithoutBundleIDIsExcluded() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "NoID.app", bundleID: nil, name: "NoID")

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertTrue(result.isEmpty)
    }

    func testMissingBundleNameFallsBackToFileName() async throws {
        let apps = try makeTempDir()
        try makeApp(in: apps, fileName: "Baz.app", bundleID: "com.baz.Qux", name: nil)

        let result = await AppDiscovery().discover(appsDirectories: [apps])
        XCTAssertEqual(result.first?.name, "Baz")
    }

    func testDuplicateBundleIDAcrossDirsIsDeduped() async throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        try makeApp(in: dir1, fileName: "Foo.app", bundleID: "com.dup.App", name: "Foo")
        try makeApp(in: dir2, fileName: "Foo.app", bundleID: "com.dup.App", name: "Foo")

        let result = await AppDiscovery().discover(appsDirectories: [dir1, dir2])
        XCTAssertEqual(result.count, 1)
    }
}
