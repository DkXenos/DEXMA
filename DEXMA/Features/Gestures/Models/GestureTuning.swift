import CoreGraphics

/// The two-finger tab swipe's constants (see `TabSwipeTracker` and
/// `NotchViewModel.endTabSwipe`), in one place for tuning.
nonisolated struct GestureTuning: Equatable {
    /// Finger travel (pt of scroll) before deciding between a tab swipe and a scroll.
    var axisLockDistance: CGFloat = 8
    /// Horizontal wins once |dx| is more than this many times |dy|.
    var horizontalRatio: CGFloat = 1.5
    /// Released past this fraction of a page: on to the next tab.
    var commitFraction: CGFloat = 0.35
    /// …or released faster than this (pages per second) toward it.
    var flickVelocity: CGFloat = 1.2
    /// Past the first and last tab the pages follow at this fraction of the fingers, up to
    /// `rubberBandLimit` of a page.
    var rubberBand: CGFloat = 0.3
    var rubberBandLimit: CGFloat = 0.12

    static let standard = GestureTuning()
}
