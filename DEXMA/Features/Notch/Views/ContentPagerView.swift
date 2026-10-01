import AppKit

/// The content card's pages side by side, one per tab (terminal, Search…), at the card's
/// fixed size. The card shows one page, or two while a swipe moves between them: the pager is
/// scrolled by its bounds' origin (one property per frame), so the pages themselves never move
/// or resize. Clipped to the card's rounded rect and, with a layer mask, to the notch
/// silhouette, which also carries the content fade.
///
/// Pages off the card are hidden (so they don't draw), and every page is hidden while the panel
/// is fully closed.
final class ContentPagerView: NSView {
    private(set) var pages: [NSView] = []
    private let maskLayer = CAShapeLayer()
    private(set) var progress: CGFloat = 0
    /// The selected tab's page: always shown (with the panel), so it can take the keyboard
    /// the moment it's selected, before it has slid in.
    var selectedIndex = 0 {
        didSet { if selectedIndex != oldValue { updateVisibility() } }
    }
    /// False while the panel is fully closed: nothing shows.
    var isShowingPages = false {
        didSet { if isShowingPages != oldValue { updateVisibility() } }
    }

    init(size: CGSize, cornerRadius: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous  // Like the card's stroke (SwiftUI's .continuous).
        layer?.masksToBounds = true
        layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setPages(_ views: [NSView]) {
        pages.forEach { $0.removeFromSuperview() }
        pages = views
        for view in views { addSubview(view) }
        layoutPages()
    }

    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set { layer?.cornerRadius = newValue }
    }

    func resize(to size: CGSize) {
        guard frame.size != size else { return }
        setFrameSize(size)
        layoutPages()
    }

    /// Scrolls to `progress` (0 = first page; fractional between two; may overshoot a little
    /// past either end while rubber-banding).
    func setProgress(_ value: CGFloat) {
        guard value != progress else { return }
        progress = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setBoundsOrigin(CGPoint(x: (value * bounds.width).rounded(), y: 0))
        maskLayer.frame = bounds
        CATransaction.commit()
        updateVisibility()
    }

    /// Clips to `shape`, laid out in panel coordinates (top-left origin); the card's top-left
    /// corner sits at `origin` there. Called from SwiftUI's update pass: layers only.
    func update(mask shape: NotchShape, panelSize: CGSize, origin: CGPoint, opacity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        maskLayer.path = shape.maskPath(panelSize: panelSize, origin: origin, viewHeight: bounds.height)
        // The mask's opacity scales the content's alpha: that's the fade.
        maskLayer.opacity = Float(opacity)
        CATransaction.commit()
    }

    private func layoutPages() {
        let size = bounds.size
        for (index, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
        }
        setBoundsOrigin(CGPoint(x: (progress * size.width).rounded(), y: 0))
        updateVisibility()
    }

    /// Launch: every page shown for a moment while the panel is closed (invisible: the mask's
    /// opacity is 0), so each web view's first appearance (WebKit's first layer tree) happens
    /// now, not on the first swipe.
    func prewarm(for duration: TimeInterval) {
        for page in pages where page.isHidden { page.isHidden = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.updateVisibility() }
    }

    private func updateVisibility() {
        for (index, page) in pages.enumerated() {
            let hidden = !isShowingPages || (abs(CGFloat(index) - progress) >= 0.999 && index != selectedIndex)
            if page.isHidden != hidden { page.isHidden = hidden }
        }
    }
}
