import CoreGraphics

/// The terminal's context in the band right of the notch: the working directory (`~` for home,
/// the middle cut out if it's still too wide) right-aligned, and before it the running dot.
/// Computed once for both the band's text and the pulsing dot drawn over it. Pure.
nonisolated struct TerminalContextLayout: Equatable {
    static let dot: CGFloat = 6
    static let dotSpacing: CGFloat = 6
    /// Kept clear next to the notch.
    static let notchMargin: CGFloat = 10
    static let fontSize: CGFloat = 11
    static let textHeight: CGFloat = 14

    let text: String
    /// Panel coordinates (top-left origin).
    let textFrame: CGRect
    let dotFrame: CGRect

    init(directory: String, home: String, region: CGRect, measure: (String) -> CGFloat) {
        let available = max(region.width - Self.notchMargin - Self.dot - Self.dotSpacing, 0)
        let full = PathAbbreviation.abbreviate(directory, home: home)
        let text = directory.isEmpty ? "" : PathAbbreviation.fitMiddle(full, maxWidth: available, measure: measure)
        let width = min(measure(text).rounded(.up), available)
        self.text = text
        textFrame = CGRect(x: region.maxX - width, y: region.midY - Self.textHeight / 2,
                           width: width, height: Self.textHeight)
        dotFrame = CGRect(x: textFrame.minX - Self.dotSpacing - Self.dot, y: region.midY - Self.dot / 2,
                          width: Self.dot, height: Self.dot)
    }
}
