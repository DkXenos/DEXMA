import CoreGraphics

/// The capture controls at the right end of the band, on every tab: the Capture button, and
/// before it (while a capture waits for claude.ai) a thumbnail chip with a discard ✕. The
/// tab's context gets what's left of the region. Pure.
nonisolated enum CaptureBandLayout {
    static let buttonSize = CGSize(width: 32, height: 28)
    static let chipHeight: CGFloat = 20
    static let chipRadius: CGFloat = 6
    static let chipMinWidth: CGFloat = 20
    static let chipMaxWidth: CGFloat = 36
    static let discardSize = CGSize(width: 16, height: 20)
    static let spacing: CGFloat = 4

    /// The thumbnail's width for a picture `aspect` (width / height) wide, 20 pt tall.
    static func chipWidth(aspect: CGFloat) -> CGFloat {
        min(max((chipHeight * aspect).rounded(), chipMinWidth), chipMaxWidth)
    }

    /// Everything the controls take from the right end of the band, with the gap before them.
    /// `chipAspect`: the waiting capture's aspect, nil without one.
    static func width(chipAspect: CGFloat?) -> CGFloat {
        var width = spacing + buttonSize.width
        if let chipAspect { width += chipWidth(aspect: chipAspect) + 2 + discardSize.width + spacing }
        return width
    }
}
