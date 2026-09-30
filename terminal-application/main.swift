import AppKit

// Pure AppKit entry point. A SwiftUI `App` would bring a scene graph, a Settings window
// and a default main menu (⌘Q, ⌘W, ⌘,) — none of which a notch utility wants.
// Top-level code is nonisolated but always runs on the main thread.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    // `NSApplication.delegate` is weak: keep ours alive for as long as the app runs.
    withExtendedLifetime(delegate) {
        NSApplication.shared.run()
    }
}
