import CoreGraphics

/// The page dots below the card, like iOS: one dot per tab, the selected one stretched into a
/// capsule; its position and width follow the tab progress. Pure.
nonisolated struct PageDotsLayout: Equatable {
    static let dot: CGFloat = 5
    static let activeWidth: CGFloat = 14
    static let spacing: CGFloat = 6
    static let opacity: CGFloat = 0.25
    static let activeOpacity: CGFloat = 0.85

    struct Dot: Equatable {
        /// Relative to the dots' centre.
        var frame: CGRect
        var opacity: CGFloat
    }

    let dots: [Dot]

    init(count: Int, progress: CGFloat) {
        let p = min(max(progress, 0), CGFloat(max(count - 1, 0)))
        let widths = (0..<count).map { index -> CGFloat in
            let reveal = max(0, 1 - abs(p - CGFloat(index)))
            return Self.dot + (Self.activeWidth - Self.dot) * reveal
        }
        let total = widths.reduce(0, +) + CGFloat(max(count - 1, 0)) * Self.spacing
        var x = -total / 2
        var dots: [Dot] = []
        for (index, width) in widths.enumerated() {
            let reveal = max(0, 1 - abs(p - CGFloat(index)))
            dots.append(Dot(frame: CGRect(x: x, y: -Self.dot / 2, width: width, height: Self.dot),
                            opacity: Self.opacity + (Self.activeOpacity - Self.opacity) * reveal))
            x += width + Self.spacing
        }
        self.dots = dots
    }
}
