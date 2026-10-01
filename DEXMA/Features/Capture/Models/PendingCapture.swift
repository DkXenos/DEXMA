import Foundation

/// A capture that couldn't go into claude.ai's message box yet (still loading, signed out): the
/// band shows it as a chip until it's attached or discarded.
struct PendingCapture: Identifiable {
    enum State: Equatable {
        /// Attaches by itself as soon as the message box is there (for up to a minute).
        case waiting
        /// Gave up waiting, or attaching failed: a click on the chip tries again.
        case needsRetry
    }

    let id = UUID()
    let image: CapturedImage
    var state: State
}
