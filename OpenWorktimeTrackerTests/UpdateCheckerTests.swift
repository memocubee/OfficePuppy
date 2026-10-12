import XCTest

@testable import OpenWorktimeTracker

final class UpdateCheckerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "update-checker-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testVersionFromTag() {
        XCTAssertEqual(UpdateChecker.version(fromTag: "zh-v0.7.9"), "0.7.9")
        XCTAssertEqual(UpdateChecker.version(fromTag: "v1.2"), "1.2")
        XCTAssertEqual(UpdateChecker.version(fromTag: "0.8.0"), "0.8.0")
        XCTAssertNil(UpdateChecker.version(fromTag: "zh-latest"))
    }

    func testNewerComparesEachNumber() {
        XCTAssertTrue(UpdateChecker.isNewer("0.7.10", than: "0.7.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.8", than: "0.7.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.7.9", than: "0.7.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.7.8", than: "0.7.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
    }

    func testReleaseFromGitHubJSON() throws {
        let json = """
            {"tag_name": "zh-v0.7.9", "draft": false, "prerelease": false,
             "html_url": "https://github.com/memocubee/OpenWorktimeTracker/releases/tag/zh-v0.7.9"}
            """
        let release = try XCTUnwrap(UpdateChecker.release(from: Data(json.utf8)))
        XCTAssertEqual(release.version, "0.7.9")
        XCTAssertEqual(release.page.lastPathComponent, "zh-v0.7.9")
    }

    func testPrereleaseAndBrokenJSONAreIgnored() {
        let prerelease = """
            {"tag_name": "zh-v0.8.0", "draft": false, "prerelease": true,
             "html_url": "https://github.com/memocubee/OpenWorktimeTracker/releases/tag/zh-v0.8.0"}
            """
        XCTAssertNil(UpdateChecker.release(from: Data(prerelease.utf8)))
        XCTAssertNil(UpdateChecker.release(from: Data("{\"message\": \"Not Found\"}".utf8)))
    }

    func testNewerReleaseShowsAndNotifiesOncePerVersion() throws {
        var notified: [String] = []
        let checker = UpdateChecker(currentVersion: "0.7.9", defaults: defaults) { notified.append($0) }
        let page = try XCTUnwrap(URL(string: "https://github.com/memocubee/OpenWorktimeTracker/releases"))
        let newer = UpdateChecker.Release(version: "0.7.10", page: page)

        checker.handle(newer)
        checker.handle(newer)
        XCTAssertEqual(checker.available, newer)
        XCTAssertEqual(notified, ["0.7.10"])

        checker.handle(UpdateChecker.Release(version: "0.8.0", page: page))
        XCTAssertEqual(notified, ["0.7.10", "0.8.0"])
    }

    func testSameOrOlderReleaseShowsNothing() throws {
        var notified: [String] = []
        let checker = UpdateChecker(currentVersion: "0.7.9", defaults: defaults) { notified.append($0) }
        let page = try XCTUnwrap(URL(string: "https://github.com/memocubee/OpenWorktimeTracker/releases"))

        checker.handle(UpdateChecker.Release(version: "0.7.9", page: page))
        checker.handle(UpdateChecker.Release(version: "0.7.8", page: page))
        XCTAssertNil(checker.available)
        XCTAssertTrue(notified.isEmpty)
    }
}
