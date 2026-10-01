import Foundation
import Testing
@testable import DEXMA

struct DefaultsMigrationTests {
    @Test func copiesLegacyValuesOnceWithoutOverwriting() throws {
        let current = "dexma.tests.current.\(UUID().uuidString)"
        let legacy = "dexma.tests.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: current))
        defer {
            defaults.removePersistentDomain(forName: current)
            defaults.removePersistentDomain(forName: legacy)
        }
        defaults.setPersistentDomain(["panelWidth": 900.0, "bounce": 0.1], forName: legacy)
        defaults.set(0.3, forKey: "bounce")  // Already set under the new identifier: kept.

        let copied = DefaultsMigration.run(into: defaults, currentDomain: current, legacyDomain: legacy)
        #expect(copied == 1)
        #expect(defaults.double(forKey: "panelWidth") == 900)
        #expect(defaults.double(forKey: "bounce") == 0.3)

        defaults.setPersistentDomain(["panelWidth": 500.0], forName: legacy)
        #expect(DefaultsMigration.run(into: defaults, currentDomain: current, legacyDomain: legacy) == 0)
        #expect(defaults.double(forKey: "panelWidth") == 900)
    }

    @Test func doesNothingUnderTheLegacyIdentifier() {
        #expect(DefaultsMigration.run(currentDomain: DefaultsMigration.legacyDomain) == 0)
    }
}
