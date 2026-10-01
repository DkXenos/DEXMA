import CoreGraphics

/// What a two-finger swipe drives: the notch panel (`NotchViewModel`). The gesture engine
/// knows only this, not the panel or the terminal.
protocol SwipeTarget: AnyObject {
    /// Open, only a swipe up (closing) counts; otherwise a swipe down from the top edge.
    var isOpen: Bool { get }
    /// A swipe up may close it right now.
    var canCloseBySwipe: Bool { get }
    /// Fingers landed where a swipe starts: a motion may follow.
    func prepareForMotion()
    func beginInteraction()
    /// `delta`: progress change since `beginInteraction`, straight from the fingers (1:1).
    func updateInteraction(delta: CGFloat)
    /// Fingers lifted (or the gesture was cancelled, with zero velocity).
    func endInteraction(velocity: CGFloat)
}
