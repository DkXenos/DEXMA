import Foundation

/// Settings live in a UserDefaults domain named after the bundle identifier. When the
/// identifier changes (the app shipped as "terminal-application" before it was DEXMA), the
/// old domain's values are copied over once so the user's settings survive. Must run before
/// anything reads UserDefaults.
nonisolated enum DefaultsMigration {
    static let legacyDomain = "com.jasontio.terminal-application"
    static let migratedKey = "didMigrateLegacyDefaults"

    /// Copies every key the current domain doesn't have yet. Returns how many were copied.
    /// Does nothing while the app still runs under the legacy identifier.
    @discardableResult
    static func run(into defaults: UserDefaults = .standard,
                    currentDomain: String? = Bundle.main.bundleIdentifier,
                    legacyDomain: String = legacyDomain) -> Int {
        guard let currentDomain, currentDomain != legacyDomain,
              !defaults.bool(forKey: migratedKey) else { return 0 }
        let existing = defaults.persistentDomain(forName: currentDomain) ?? [:]
        var copied = 0
        for (key, value) in defaults.persistentDomain(forName: legacyDomain) ?? [:]
        where existing[key] == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        defaults.set(true, forKey: migratedKey)
        return copied
    }
}
