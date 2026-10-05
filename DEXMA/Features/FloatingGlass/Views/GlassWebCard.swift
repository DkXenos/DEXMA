import AppKit

/// The conversation card's content: claude.ai's page (the Claude tab's card, moved here while
/// Claude is in floating glass), above the SwiftUI glass card and clipped to its corners. An AppKit
/// overlay at a fixed frame, so the web view is never re-parented or resized while the glass
/// morphs; it fades in once the card has grown and out before it shrinks (Core Animation).
/// With a see-through page a faint dimming layer under it keeps the text legible over bright
/// backgrounds.
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
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// Holds `view` (the Claude card) filling the card.
    func adopt(_ view: NSView) {
        page = view
        addSubview(view)
        view.frame = bounds
        view.isHidden = false  // The notch's pager hides the pages it isn't showing.
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
        dim.frame = bounds
        // Set outright (an autoresized web view can double its size, see AppKit pitfalls).
        page?.frame = bounds
    }

    /// Out of sight, so the page stops drawing (hiding a web view costs WebKit ~25 ms on the main
    /// thread: done once the card's animation is over, never during it).
    func hideWhenFaded() {
        guard let layer, layer.opacity == 0, layer.animation(forKey: "fade") == nil else { return }
        isHidden = true
    }

    /// Fades the page in (`shown`) or out (still in the view tree: `hideWhenFaded` takes it out
    /// once nothing animates).
    func setShown(_ shown: Bool, duration: Double, delay: Double = 0, completion: (() -> Void)? = nil) {
        guard let layer else { return }
        if shown { isHidden = false }
        let from = layer.presentation()?.opacity ?? layer.opacity
        let to: Float = shown ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()
        let generation = fadeGeneration + 1
        fadeGeneration = generation
        let finish = { [weak self] in
            guard let self, generation == self.fadeGeneration else { return }
            completion?()
        }
        guard duration > 0 || delay > 0 else {
            layer.removeAnimation(forKey: "fade")
            finish()
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(finish)
        layer.add(animation, forKey: "fade")
        CATransaction.commit()
    }

    private var fadeGeneration = 0
}
