import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.openworktimetracker.app", category: "Updates")

/// zh-Hant fork: Sparkle stays off so upstream releases never replace this
/// build. Instead the app looks at the fork's latest GitHub release now and
/// then, and tells the user when a newer version is out. It never downloads
/// or installs anything; the notice only opens the release page.
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    /// The newer release found by the last check, if any.
    private(set) var available: Release?

    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notify: (String) -> Void
    @ObservationIgnored private var lastCheck: Date?

    static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/memocubee/OpenWorktimeTracker/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/memocubee/OpenWorktimeTracker/releases/latest")!
    static let notificationIdentifier = "update-available"
    private static let checkInterval: TimeInterval = 12 * 3600
    private static let notifiedVersionKey = "updateNotifiedVersion"

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0",
        defaults: UserDefaults = .standard,
        notify: @escaping (String) -> Void = { NotificationManager.shared.sendUpdateNotification(version: $0) }
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.notify = notify
    }

    private var isEnabled: Bool {
        defaults.object(forKey: AppSettingsKey.updateCheckEnabled) as? Bool ?? AppDefaults.updateCheckEnabled
    }

    /// Asks GitHub at most every twelve hours; called at launch and whenever
    /// the popover opens, so a menu bar app that runs for days still checks.
    func checkIfNeeded(now: Date = Date()) {
        guard isEnabled else {
            available = nil
            return
        }
        if let lastCheck, now.timeIntervalSince(lastCheck) < Self.checkInterval { return }
        lastCheck = now

        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                let release = Self.release(from: data)
            else {
                logger.info("No release info: \(error?.localizedDescription ?? "unexpected response")")
                return
            }
            DispatchQueue.main.async { self.handle(release) }
        }.resume()
    }

    func handle(_ release: Release) {
        guard Self.isNewer(release.version, than: currentVersion) else {
            available = nil
            return
        }
        available = release
        // One system notification per version; the popover keeps showing it.
        guard defaults.string(forKey: Self.notifiedVersionKey) != release.version else { return }
        defaults.set(release.version, forKey: Self.notifiedVersionKey)
        notify(release.version)
    }

    // MARK: - Parsing

    /// The published, non-prerelease release in GitHub's "latest release" JSON.
    static func release(from data: Data) -> Release? {
        struct Payload: Decodable {
            let tagName: String
            let htmlUrl: URL
            let draft: Bool?
            let prerelease: Bool?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
            payload.draft != true, payload.prerelease != true,
            let version = version(fromTag: payload.tagName)
        else { return nil }
        return Release(version: version, page: payload.htmlUrl)
    }

    /// "zh-v0.7.9" → "0.7.9"; nil when the tag holds no version number.
    static func version(fromTag tag: String) -> String? {
        guard let start = tag.firstIndex(where: \.isNumber) else { return nil }
        let version = tag[start...].prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }

    /// Compares dotted numbers part by part, so 0.7.10 is newer than 0.7.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
