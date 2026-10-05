import CoreGraphics

/// The floating glass window's numbers, in points. The field matches Spotlight on macOS 26,
/// measured from pictures of it on the reference Mac (1512 × 982 pt, 2026-10-05; see CLAUDE.md,
/// "Floating Glass"); the buttons, the card's gap and the chip are the spec's (Spotlight's own
/// can't be measured: its mode buttons didn't show, and its results share the field's shape).
nonisolated enum GlassMetrics {
    /// Spotlight's field: 640 × 56, a capsule.
    static let fieldWidth: CGFloat = 640
    static let fieldHeight: CGFloat = 56
    /// The field's top edge, as a share of the screen's height from its top (Spotlight: 203 of 982).
    static let fieldTopFraction: CGFloat = 203.0 / 982.0
    /// Spotlight's magnifier: an ink box 22.5 pt square starting 20.5 pt in, centred vertically.
    static let iconInset: CGFloat = 20.5
    static let iconBox: CGFloat = 22.5
    /// The symbol's point size that draws a ~22.5 pt glyph (Spotlight's magnifier); measured: 20
    /// drew the sparkle's ink 19 pt.
    static let iconPointSize: CGFloat = 24
    /// The first line's top inset in the 56 pt field: puts the text's cap top at 18 pt and its
    /// baseline at 37 pt, like Spotlight's.
    static let textTopInset: CGFloat = 11.5
    /// Spotlight's text: SF Pro 26 regular, starting 61 pt in (18 pt after the icon).
    static let fontSize: CGFloat = 26
    static let textInset: CGFloat = 61
    /// Lines the field grows to (⇧Return) before it scrolls.
    static let maxLines = 5
    /// Round glass buttons right of the field, like Spotlight's mode buttons.
    static let buttonSize: CGFloat = 40
    static let buttonGap: CGFloat = 8
    static let buttonSymbolSize: CGFloat = 15
    /// The conversation card below the field: Spotlight's results radius (28, measured), the
    /// spec's gap (Spotlight has none: its results grow out of the field's own shape).
    static let cardGap: CGFloat = 8
    static let cardRadius: CGFloat = 28
    /// The card is at most this share of the screen's height, and stops this far above the
    /// Dock / the screen's bottom.
    static let cardMaxFraction: CGFloat = 0.6
    static let cardMinHeight: CGFloat = 220
    static let bottomMargin: CGFloat = 16
    /// A capture waiting for the question: a thumbnail at the field's left.
    static let chipSize: CGFloat = 32
    static let chipRadius: CGFloat = 8
    static let chipTextGap: CGFloat = 10
    /// Room around the shapes for the glass's shadow (Spotlight's window keeps 40 pt).
    static let shadowMargin: CGFloat = 40
    /// Glass shapes within this distance morph into each other (= the gaps: they never blend
    /// at rest, but the buttons and the card grow out of the field).
    static let containerSpacing: CGFloat = 8
}
