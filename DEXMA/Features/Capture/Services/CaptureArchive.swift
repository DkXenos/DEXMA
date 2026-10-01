import Foundation
import os

/// The optional copy of each capture in ~/Pictures/DEXMA (Settings: "Also save captures"). Off
/// by default: captures otherwise never touch the disk.
enum CaptureArchive {
    nonisolated private static let logger = Logger(category: "Capture")

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/DEXMA", isDirectory: true)
    }

    /// Writes `png` as "DEXMA Capture <date> at <time>.png" in the background.
    static func save(_ png: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "DEXMA Capture \(formatter.string(from: Date())).png"
        let folder = folder
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var url = folder.appendingPathComponent(name)
                var copy = 2
                while FileManager.default.fileExists(atPath: url.path) {
                    url = folder.appendingPathComponent(name.replacingOccurrences(of: ".png", with: " \(copy).png"))
                    copy += 1
                }
                try png.write(to: url, options: .atomic)
            } catch {
                logger.error("Saving a capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
