import XCTest

@testable import OfficePuppy

final class LegacyMigrationTests: XCTestCase {
    private var suiteName = ""
    private var legacyName = ""
    private var defaults: UserDefaults!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        suiteName = "migration-new-\(UUID())"
        legacyName = "migration-old-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyName)
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testCopiesSettingsButNotPerInstallState() {
        defaults.setPersistentDomain(
            [
                "orangeThresholdHours": 8.5, "menuBarSelectedTab": "records",
                "hasLaunchedBefore": true, "launchAtLogin": true, "SULastCheckTime": Date(),
                "NSNavPanelExpandedSizeForOpenMode": "{880, 448}",
            ], forName: legacyName)

        LegacyMigration.runIfNeeded(defaults: defaults, legacyDomain: legacyName, dataFolders: [])

        XCTAssertEqual(defaults.double(forKey: "orangeThresholdHours"), 8.5)
        XCTAssertEqual(defaults.string(forKey: "menuBarSelectedTab"), "records")
        for key in ["hasLaunchedBefore", "launchAtLogin", "SULastCheckTime", "NSNavPanelExpandedSizeForOpenMode"] {
            XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[key], key)
        }
    }

    func testRunsOnlyOnce() {
        defaults.setPersistentDomain(["menuBarSelectedTab": "records"], forName: legacyName)
        LegacyMigration.runIfNeeded(defaults: defaults, legacyDomain: legacyName, dataFolders: [])
        defaults.set("today", forKey: "menuBarSelectedTab")

        LegacyMigration.runIfNeeded(defaults: defaults, legacyDomain: legacyName, dataFolders: [])

        XCTAssertEqual(defaults.string(forKey: "menuBarSelectedTab"), "today")
    }

    func testRenewsTheChosenLogFolder() throws {
        let logs = tempDirectory.appendingPathComponent("my logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let oldBookmark = try logs.bookmarkData()
        defaults.setPersistentDomain([AppSettingsKey.logFolderBookmark: oldBookmark], forName: legacyName)

        LegacyMigration.runIfNeeded(defaults: defaults, legacyDomain: legacyName, dataFolders: [])

        let renewed = try XCTUnwrap(defaults.data(forKey: AppSettingsKey.logFolderBookmark))
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: renewed, options: .withSecurityScope, relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        XCTAssertEqual(resolved.standardizedFileURL.path, logs.standardizedFileURL.path)
    }

    func testCopiesTheDataFolderWithoutOverwriting() throws {
        let old = tempDirectory.appendingPathComponent("Old", isDirectory: true)
        let new = tempDirectory.appendingPathComponent("New", isDirectory: true)
        let kept = tempDirectory.appendingPathComponent("Kept", isDirectory: true)
        for folder in [old, kept] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("logs"), withIntermediateDirectories: true)
        }
        try Data("old".utf8).write(to: old.appendingPathComponent("logs/2026-10-12.json"))
        try Data("kept".utf8).write(to: kept.appendingPathComponent("logs/2026-10-12.json"))

        LegacyMigration.runIfNeeded(
            defaults: defaults, legacyDomain: legacyName, dataFolders: [(old, new), (old, kept)])

        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("logs/2026-10-12.json"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: kept.appendingPathComponent("logs/2026-10-12.json"), encoding: .utf8), "kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path), "The old folder stays as a backup")
    }
}
