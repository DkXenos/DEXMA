import AppKit

/// Force Touch trackpad ticks for the swipe, like the system's own gestures. They're only felt
/// while a finger is on the trackpad, so they're played for gesture-driven motion only.
enum Haptics {
    /// Crossing the point where letting go commits to opening (or closing).
    static func threshold() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// The panel snapping into place, open or closed.
    static func snap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
