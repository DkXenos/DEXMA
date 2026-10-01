import Foundation
import os

extension Logger {
    /// A logger in DEXMA's subsystem (its bundle identifier), for `category`.
    nonisolated init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "DEXMA", category: category)
    }
}
