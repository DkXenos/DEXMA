import AppKit

/// Where the Claude tab goes instead of the notch (the floating glass window implements it):
/// selecting Claude in the notch — a click, ⌘3, ⌃Tab or a swipe — collapses the notch and
/// presents it there.
protocol ClaudeTabRedirect: AnyObject {
    /// The notch has collapsed (keeping the keyboard until this takes it): show Claude.
    func presentClaude()
}
