import CoreGraphics

/// What capture needs from the notch panel (`NotchViewModel` implements it): to step aside while
/// the user draws, where the notch is to fly into, and the Claude tab to land in.
protocol CaptureHandoffTarget: AnyObject {
    /// Capture is starting: the panel collapses if it's open, and ignores the pointer meanwhile.
    func captureWillBegin()
    /// Capture is over (handed off or cancelled).
    func captureDidEnd()
    /// Where the notch will be (global AppKit coordinates) when the panel opens, if that's on the
    /// display with `screenFrame`; nil if it opens on another display.
    func captureLanding(onScreen screenFrame: CGRect) -> CGRect?
    /// The picture is on its way into the notch: get the screen warp ready for the open.
    func prepareForCaptureLanding()
    /// The picture reached the notch: open, on the Claude tab.
    func openForCapture()
    /// The Claude tab, from the chip's retry: selected, and the panel opened if it isn't.
    func showClaudeTab()
    /// The Claude tab is open and at rest with the keyboard: a paste lands in its page.
    var isClaudeReadyForInsert: Bool { get }
    /// The Claude page changed (an attachment went in): its picture for the liquid effect is stale.
    func claudeContentDidChange()
    /// The band's chip came or went: the tab's context has a different width.
    func captureChipDidChange()
}
