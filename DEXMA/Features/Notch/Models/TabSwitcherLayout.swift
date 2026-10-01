import CoreGraphics

/// The tab switcher's geometry at a tab progress, Dynamic-Island style: a container pill with
/// one segment per tab. The selected tab expands to icon + label, the others are icon-only, and
/// the selection indicator sits behind the expanded one; mid-swipe every width, the label
/// reveal and the indicator interpolate, so half a swipe shows a half-expanded state. Pure.
nonisolated struct TabSwitcherLayout: Equatable {
    static let padding: CGFloat = 3
    static let gap: CGFloat = 4
    static let cornerRadius: CGFloat = 10
    static let indicatorRadius: CGFloat = 8
    static let tabHeight: CGFloat = 26
    static let inactiveWidth: CGFloat = 30
    static let iconSize: CGFloat = 12
    /// The icon's box: centred in an inactive tab, `labelPadding` from the left when active.
    static let iconBox: CGFloat = 14
    static let labelPadding: CGFloat = 10
    static let iconLabelSpacing: CGFloat = 6
    static let labelSize: CGFloat = 12.5

    struct Tab: Equatable {
        /// In the container (top-left origin).
        var frame: CGRect
        /// 0 (icon only) … 1 (icon + label, fully selected).
        var reveal: CGFloat
    }

    let tabs: [Tab]
    /// The indicator behind the selected tab, in the container.
    let indicator: CGRect
    /// The container pill.
    let size: CGSize
    /// Labels fit (otherwise every tab stays icon-only, the indicator still moves).
    let labelled: Bool

    /// An expanded tab's width for a label `labelWidth` wide: hugs icon and label.
    static func activeWidth(labelWidth: CGFloat) -> CGFloat {
        labelPadding + iconBox + iconLabelSpacing + labelWidth.rounded(.up) + labelPadding
    }

    /// `activeWidths`: each tab's expanded width; `available`: the band region's width.
    init(activeWidths: [CGFloat], progress: CGFloat, available: CGFloat) {
        let count = activeWidths.count
        let widest = activeWidths.max() ?? Self.inactiveWidth
        let full = 2 * Self.padding + CGFloat(max(count - 1, 0)) * (Self.inactiveWidth + Self.gap) + widest
        labelled = full <= available
        let p = min(max(progress, 0), CGFloat(max(count - 1, 0)))
        var x = Self.padding
        var tabs: [Tab] = []
        for (index, active) in activeWidths.enumerated() {
            let reveal = max(0, 1 - abs(p - CGFloat(index)))
            let width = labelled ? Self.inactiveWidth + (active - Self.inactiveWidth) * reveal : Self.inactiveWidth
            tabs.append(Tab(frame: CGRect(x: x, y: Self.padding, width: width, height: Self.tabHeight),
                            reveal: reveal))
            x += width + Self.gap
        }
        self.tabs = tabs
        size = CGSize(width: x - Self.gap + Self.padding, height: Self.tabHeight + 2 * Self.padding)
        if tabs.isEmpty {
            indicator = .zero
        } else {
            let lower = Int(p.rounded(.down))
            let upper = min(lower + 1, tabs.count - 1)
            let t = p - CGFloat(lower)
            let a = tabs[lower].frame, b = tabs[upper].frame
            indicator = CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY,
                               width: a.width + (b.width - a.width) * t, height: a.height)
        }
    }
}
