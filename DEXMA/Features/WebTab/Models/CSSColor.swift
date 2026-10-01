import CoreGraphics
import Foundation

/// A colour as `getComputedStyle` reports it (`rgb(28, 28, 30)`, `rgba(0, 0, 0, 0)`). Pure.
nonisolated struct CSSColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    /// Components 0…1; nil if it isn't an `rgb()`/`rgba()` colour.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")"),
              trimmed.hasPrefix("rgb") else { return nil }
        let inside = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = inside.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        red = CGFloat(parts[0]) / 255
        green = CGFloat(parts[1]) / 255
        blue = CGFloat(parts[2]) / 255
        alpha = parts.count == 4 ? CGFloat(parts[3]) : 1
    }

    /// Fully transparent: the page shows what's behind it there.
    var isTransparent: Bool { alpha < 0.01 }
}
