import XCTest
@testable import GlanceCore

final class UninstallSafetyTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceUninstallSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    // MARK: App

    func testAppBundleDirectlyUnderAppsDirIsDeletable() throws {
        let apps = try makeTempDir()
        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertTrue(UninstallSafety.isDeletableApp(app, within: [apps]))
    }

    func testNonAppExtensionIsNotDeletableApp() throws {
        let apps = try makeTempDir()
        let notApp = apps.appendingPathComponent("Foo.txt")
        XCTAssertFalse(UninstallSafety.isDeletableApp(notApp, within: [apps]))
    }

    func testNestedAppIsNotDeletableApp() throws {
        // 只允許直接子項;apps/sub/Foo.app 不可。
        let apps = try makeTempDir()
        let nested = apps.appendingPathComponent("sub/Foo.app", isDirectory: true)
        XCTAssertFalse(UninstallSafety.isDeletableApp(nested, within: [apps]))
    }

    func testAppsDirItselfIsNotDeletableApp() throws {
        let apps = try makeTempDir()
        XCTAssertFalse(UninstallSafety.isDeletableApp(apps, within: [apps]))
    }

    func testAppOutsideAppsDirIsNotDeletable() throws {
        let apps = try makeTempDir()
        let outside = try makeTempDir()
        let stray = outside.appendingPathComponent("Foo.app", isDirectory: true)
        XCTAssertFalse(UninstallSafety.isDeletableApp(stray, within: [apps]))
    }

    // MARK: Related

    func testRelatedDirectlyUnderSupportDirIsDeletable() throws {
        let support = try makeTempDir()
        let file = support.appendingPathComponent("com.foo.Bar.plist")
        XCTAssertTrue(UninstallSafety.isDeletableRelated(file, within: [support]))
    }

    func testSupportDirItselfIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        XCTAssertFalse(UninstallSafety.isDeletableRelated(support, within: [support]))
    }

    func testRelatedOutsideSupportDirIsNotDeletable() throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let stray = outside.appendingPathComponent("com.foo.Bar")
        XCTAssertFalse(UninstallSafety.isDeletableRelated(stray, within: [support]))
    }

    func testTraversalEscapeIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        let escape = support.appendingPathComponent("../com.foo.Bar")
        XCTAssertFalse(UninstallSafety.isDeletableRelated(escape, within: [support]))
    }

    func testSymlinkIsNotDeletableRelated() throws {
        let support = try makeTempDir()
        let outside = try makeTempDir()
        let target = outside.appendingPathComponent("real")
        try Data().write(to: target)
        let link = support.appendingPathComponent("com.foo.Bar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertFalse(UninstallSafety.isDeletableRelated(link, within: [support]))
    }
}
