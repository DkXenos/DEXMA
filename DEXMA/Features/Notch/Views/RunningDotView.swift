import AppKit
import QuartzCore

/// The green dot before the terminal's working directory while a command runs, pulsing slowly
/// and subtly. An AppKit view over the panel's SwiftUI content, animated by Core Animation in
/// the render server: no main-thread work for as long as the command runs (a SwiftUI animation
/// would redraw the band every frame). Shown only with the panel open and still; while it
/// moves, the band draws the dot itself so the liquid effect bends it.
final class RunningDotView: NSView {
    static let color = NSColor.systemGreen

    private let dot = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.backgroundColor = Self.color.cgColor
        layer?.addSublayer(dot)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Where it is (in its superview, the panel's flipped content view) and how visible
    /// (the terminal tab's share of the band's crossfade); hidden at 0.
    func update(frame newFrame: CGRect, visibility: CGFloat) {
        if frame != newFrame {
            frame = newFrame
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.frame = bounds
            dot.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }
        let hidden = visibility <= 0
        if hidden != isHidden {
            isHidden = hidden
            if hidden { dot.removeAllAnimations() } else { startPulse() }
        }
        if !hidden, abs(alphaValue - visibility) > 0.001 { alphaValue = visibility }
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
    }
}
