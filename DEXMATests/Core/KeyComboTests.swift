import AppKit
import Foundation
import Testing
@testable import DEXMA

struct KeyComboTests {
    /// Saved as JSON in UserDefaults: a combo must come back exactly as it was stored.
    @Test func survivesJSON() throws {
        let combo = KeyCombo(keyCode: 0x31, carbonModifiers: 0x0800, display: "⌥Space", menuKey: " ")
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
        #expect(decoded.menuModifiers == [.option])
    }
}
