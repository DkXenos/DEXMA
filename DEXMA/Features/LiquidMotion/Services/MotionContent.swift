import AppKit

/// What the motion layer stands in for while the panel moves: the selected tab's live content
/// (the terminal, or the Search card), which can take a picture of itself. The liquid effect
/// knows only this, not the terminal or the web view.
protocol MotionContent: AnyObject {
    /// A picture of the content as it looks now, cached until `invalidateSnapshot`. Called
    /// right as a motion starts, so it must be quick when the cache is fresh.
    func motionSnapshot() -> ContentSnapshot?
    /// The content may look different now: the cached picture is stale.
    func invalidateSnapshot()
    /// The content has been quiet for a moment with the panel at rest: bring the cached
    /// picture up to date (it may finish later; see `onSnapshotRefreshed`).
    func refreshSnapshot()
    /// Whether an input event of `type` that reached the panel may have changed what's shown.
    func isChanged(by type: NSEvent.EventType) -> Bool
    /// The live content is back on screen after a motion that ended open. Returns whether the
    /// cached picture must be retaken (e.g. it lacks the caret the live view now shows).
    func didReappear() -> Bool
    /// Set by the engine: a picture taken asynchronously by `refreshSnapshot` just arrived.
    var onSnapshotRefreshed: (() -> Void)? { get set }
}
