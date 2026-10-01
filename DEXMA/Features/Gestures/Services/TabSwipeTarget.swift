import CoreGraphics

/// What a two-finger horizontal swipe drives: the panel's tabs (`NotchViewModel`). The tab
/// swipe monitor knows only this.
protocol TabSwipeTarget: AnyObject {
    /// The panel is open: scroll events over it may swipe tabs.
    var acceptsTabSwipes: Bool { get }
    /// A tab page's width (pt): one page of finger travel is one tab.
    var tabPageWidth: CGFloat { get }
    /// Whether a swipe toward `direction` (+1 later tab, −1 earlier) may start at `point`
    /// (panel coordinates, top-left origin).
    func canSwipeTabs(at point: CGPoint, direction: Int) -> Bool
    func beginTabSwipe()
    /// `delta`: pages since `beginTabSwipe`, + toward later tabs.
    func updateTabSwipe(delta: CGFloat)
    /// Fingers lifted; `velocity` in pages per second.
    func endTabSwipe(delta: CGFloat, velocity: CGFloat)
}
