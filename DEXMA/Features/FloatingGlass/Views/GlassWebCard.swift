import AppKit

/// The conversation card's content: claude.ai's page (the Claude tab's card, moved here while
/// Claude is in floating glass), hosted inside the SwiftUI glass card (`GlassPage`), so the
/// system's glass transitions carry it in and out with its card, in the same frames (as an AppKit
/// overlay with its own fade it showed late on appearing and lingered after the glass on hiding:
/// measured frame by frame with `-glasstest -glassrecord`). Clipped to the card's corners.
///
/// The page keeps one size (the card's at a one-line field) and sits at the card's bottom: when
/// the field grows by a few lines the card gets shorter and the page's top is clipped, instead
/// of WebKit laying the page out again on every frame of that animation. With a see-through page
/// a faint dimming layer under it keeps the text legible over bright backgrounds.
final class GlassWebCard: NSView {
    private let dim = CALayer()
    private(set) weak var page: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = GlassMetrics.cardRadius
        layer?.cornerCurve = .circular  // Like the glass card's RoundedRectangle.
        layer?.masksToBounds = true
        layer?.opacity = 0
        dim.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(dim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// The page's size: the card's with the field at one line.
    var pageSize = CGSize(width: GlassMetrics.fieldWidth, height: GlassMetrics.cardMinHeight) {
        didSet { if pageSize != oldValue { layoutPage() } }
    }

    /// The card is closed and at rest: the page waits outside the card's bounds (clipped), so
    /// the invisible page can't take the pointer (cursor, hover). Moving it costs nothing; hiding
    /// it or taking it out of the window would make WebKit work (25–95 ms of main thread).
    var isParked = true {
        didSet { if isParked != oldValue { layoutPage() } }
    }

    /// The page fades in (after `delay`) or out over `duration`. In: out of the parking spot
    /// first. Out: parked once it's gone.
    func setVisible(_ visible: Bool, duration: Double, delay: Double = 0) {
        guard let layer else { return }
        if visible { isParked = false }
        let from = layer.presentation()?.opacity ?? layer.opacity
        let to: Float = visible ? 1 : 0
        generation += 1
        let id = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, id == self.generation, !visible else { return }
            self.isParked = true
        }
        if from != to {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = to
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if delay > 0 {
                fade.beginTime = CACurrentMediaTime() + delay
                fade.fillMode = .backwards
            }
            layer.add(fade, forKey: "fade")
        }
        CATransaction.commit()
    }

    /// At once, no animation (the panel's hidden or the state is set before showing).
    func setVisibleNow(_ visible: Bool) {
        generation += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.removeAnimation(forKey: "fade")
        layer?.opacity = visible ? 1 : 0
        CATransaction.commit()
        isParked = !visible
    }

    private var generation = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        isParked ? nil : super.hitTest(point)
    }

    /// Holds `view` (the Claude card).
    func adopt(_ view: NSView) {
        page = view
        addSubview(view)
        view.isHidden = false  // The notch's pager hides the pages it isn't showing.
        layoutPage()
    }

    /// Lets go of the page (it goes back into the notch).
    func release() {
        page?.removeFromSuperview()
        page = nil
    }

    /// How much the card's content is darkened (light mode lightened) behind a see-through page.
    var dimAmount: CGFloat = 0 {
        didSet { updateDim() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDim()
    }

    private func updateDim() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        dim.backgroundColor = CGColor(gray: dark ? 0 : 1, alpha: dimAmount)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutPage()
    }

    private func layoutPage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dim.frame = bounds
        CATransaction.commit()
        // Set outright (an autoresized web view can double its size, see AppKit pitfalls); only
        // its position follows the card's height.
        let x = isParked ? -(pageSize.width + 200) : 0
        let frame = CGRect(x: x, y: bounds.height - pageSize.height, width: pageSize.width, height: pageSize.height)
        if let page, page.frame != frame { page.frame = frame }
    }
}
