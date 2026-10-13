import Foundation
import os.log

private let logger = Logger(subsystem: "com.memocubee.officepuppy", category: "Migration")

/// One-time move from the app's former identity (OpenWorktimeTracker,
/// `com.openworktimetracker.app`) so a renamed install keeps its settings, its
/// chosen log folder and the logs in the default data folder.
enum LegacyMigration {
    static let legacyBundleIdentifier = "com.openworktimetracker.app"
    static let legacyFolderName = "OpenWorktimeTracker"
    static let folderName = "OfficePuppy"
    static let doneKey = "migratedFromOpenWorktimeTracker"

    /// Per-install state that starts fresh under the new identity: the first
    /// launch registers the login item again, and Sparkle keeps its own state.
    private static let skippedKeys: Set<String> = ["hasLaunchedBefore", "launchAtLogin", "updateNotifiedVersion"]

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        legacyDomain: String = legacyBundleIdentifier,
        dataFolders: [(from: URL, to: URL)] = defaultDataFolders()
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        if let legacy = defaults.persistentDomain(forName: legacyDomain) {
            var copied = 0
            for (key, value) in legacy where !isSkipped(key) {
                defaults.set(value, forKey: key)
                copied += 1
            }
            // The old app's security-scoped bookmark only resolves for the app
            // that made it, so resolve it plainly and bookmark the folder again.
            if let data = legacy[AppSettingsKey.logFolderBookmark] as? Data {
                if let renewed = renewedBookmark(from: data) {
                    defaults.set(renewed, forKey: AppSettingsKey.logFolderBookmark)
                } else {
                    defaults.removeObject(forKey: AppSettingsKey.logFolderBookmark)
                    logger.error("Could not carry over the chosen log folder")
                }
            }
            logger.info("Copied \(copied) settings from \(legacyDomain)")
        }

        let fileManager = FileManager.default
        for folder in dataFolders
        where fileManager.fileExists(atPath: folder.from.path) && !fileManager.fileExists(atPath: folder.to.path) {
            do {
                try fileManager.createDirectory(
                    at: folder.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Copy, not move: the old folder stays as a backup.
                try fileManager.copyItem(at: folder.from, to: folder.to)
            } catch {
                logger.error("Could not copy \(folder.from.path): \(error.localizedDescription)")
            }
        }
    }

    static func isSkipped(_ key: String) -> Bool {
        skippedKeys.contains(key) || key.hasPrefix("SU") || key.hasPrefix("NS")
    }

    static func renewedBookmark(from data: Data) -> Data? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        else { return nil }
        return try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The default data folder in Application Support and the iCloud Drive folder.
    static func defaultDataFolders() -> [(from: URL, to: URL)] {
        let fileManager = FileManager.default
        var folders: [(from: URL, to: URL)] = []
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            folders.append((support.appendingPathComponent(legacyFolderName, isDirectory: true),
                            support.appendingPathComponent(folderName, isDirectory: true)))
        }
        let iCloud = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        folders.append((iCloud.appendingPathComponent(legacyFolderName, isDirectory: true),
                        iCloud.appendingPathComponent(folderName, isDirectory: true)))
        return folders
    }
}
