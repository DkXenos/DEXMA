import CoreGraphics

/// The connect peek's pill around the notch: the notch's height + 20 pt, and as wide as the
/// notch plus two equal wings (≥ 70 pt each, wider when the text needs it, never past what the
/// panel can show). The icon is centred in the left wing, the text (one or two lines) in the
/// right one. Panel coordinates (top-left origin). Pure.
nonisolated struct ActivityPillLayout: Equatable {
    static let extraHeight: CGFloat = 20
    static let minWing: CGFloat = 70
    /// Clear space either side of the text in its wing.
    static let textInset: CGFloat = 12
    static let iconSize: CGFloat = 16
    static let fontSize: CGFloat = 13
    /// The case's line, under the buds'.
    static let secondaryFontSize: CGFloat = 11

    let size: CGSize
    let iconCenter: CGPoint
    /// The text's box, centred in the right wing (its width is the wing's, less the insets).
    let textFrame: CGRect

    /// `notch`: the notch in panel coordinates; `textWidth`: the widest line; `maxWidth`: the
    /// widest the silhouette may get.
    init(notch: CGRect, textWidth: CGFloat, maxWidth: CGFloat) {
        let widest = max((maxWidth - notch.width) / 2, 0)
        let wing = min(max(Self.minWing, textWidth.rounded(.up) + 2 * Self.textInset), widest)
        let height = notch.height + Self.extraHeight
        size = CGSize(width: notch.width + 2 * wing, height: height)
        iconCenter = CGPoint(x: notch.minX - wing / 2, y: height / 2)
        textFrame = CGRect(x: notch.maxX + Self.textInset, y: 0,
                           width: max(wing - 2 * Self.textInset, 0), height: height)
    }
}
