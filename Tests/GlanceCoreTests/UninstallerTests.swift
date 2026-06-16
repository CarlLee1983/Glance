import XCTest
@testable import GlanceCore

final class UninstallerTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDownWithError() throws {
        for t in temps { try? FileManager.default.removeItem(at: t) }
        temps.removeAll()
        try super.tearDownWithError()
    }

    private func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceUninstaller-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temps.append(dir)
        return dir
    }

    private func touch(_ url: URL, bytes: Int) throws {
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    /// 注入式假垃圾桶:把移除動作改成移到 trashDir,讓測試可斷言。
    private func fakeTrash(into trashDir: URL) -> @Sendable (URL) throws -> Void {
        { url in
            let dest = trashDir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
        }
    }

    func testTrashesAppAndRelatedAndReportsFreedBytes() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")
        let trash = try makeTempDir("trash")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try touch(app.appendingPathComponent("blob.bin"), bytes: 100)
        let related = support.appendingPathComponent("com.foo.Bar.plist")
        try touch(related, bytes: 20)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 100),
            relatedFiles: [RelatedFile(url: related, sizeBytes: 20)]
        )
        let uninstaller = Uninstaller(trash: fakeTrash(into: trash))
        let result = await uninstaller.run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 2)
        XCTAssertEqual(result.freedBytes, 120)
        XCTAssertTrue(result.skippedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: related.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Foo.app").path))
    }

    func testMaliciousRelatedOutsideSupportDirIsBlocked() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")
        let outside = try makeTempDir("outside")
        let trash = try makeTempDir("trash")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let evil = outside.appendingPathComponent("com.foo.Bar")  // 範圍外
        try touch(evil, bytes: 10)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 0),
            relatedFiles: [RelatedFile(url: evil, sizeBytes: 10)]
        )
        let result = await Uninstaller(trash: fakeTrash(into: trash)).run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 1)  // 只有 app 本體
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evil.path))  // 惡意項未被動到
    }

    func testTrashFailureGoesToSkippedWithoutAborting() async throws {
        let apps = try makeTempDir("apps")
        let support = try makeTempDir("support")

        let app = apps.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let related = support.appendingPathComponent("com.foo.Bar.plist")
        try touch(related, bytes: 20)

        let plan = UninstallPlan(
            app: InstalledApp(bundleID: "com.foo.Bar", name: "Foo", bundleURL: app, sizeBytes: 0),
            relatedFiles: [RelatedFile(url: related, sizeBytes: 20)]
        )
        // 對 app 本體拋錯、其餘成功:驗證不中斷且失敗進 skipped。
        let failingTrash: @Sendable (URL) throws -> Void = { url in
            if url.pathExtension == "app" {
                throw NSError(domain: "test", code: 1)
            }
            try FileManager.default.removeItem(at: url)
        }
        let result = await Uninstaller(trash: failingTrash).run(
            plan: plan, appsDirectories: [apps], supportDirectories: [support]
        )

        XCTAssertEqual(result.trashedCount, 1)  // related 成功
        XCTAssertEqual(result.skippedCount, 1)  // app 失敗
    }
}
