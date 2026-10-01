import AppKit

/// The panel's geometry from the settings: the screen it opens on (`DisplayChoice`) and its
/// size, never wider or taller than that screen allows.
final class NotchGeometryProvider {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Nil only when there's no screen at all.
    func makeGeometry() -> NotchGeometry? {
        guard let screen = openingScreen() else { return nil }
        // Never wider or taller than the screen allows (the panel hangs from the top edge).
        let size = CGSize(
            width: min(settings.panelWidth, screen.frame.width - 2 * NotchGeometry.margin),
            height: min(settings.panelHeight, screen.frame.height * 0.85))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forcePill") {
            let pill = NotchGeometry(screen: screen, expandedSize: size)
            return NotchGeometry(screenFrame: pill.screenFrame,
                                 notchRect: CGRect(x: pill.screenFrame.midX - NotchGeometry.pillWidth / 2,
                                                   y: pill.screenFrame.maxY - 26,
                                                   width: NotchGeometry.pillWidth, height: 26),
                                 hasNotch: false, expandedSize: size)
        }
        #endif
        return NotchGeometry(screen: screen, expandedSize: size)
    }

    private func openingScreen() -> NSScreen? {
        switch settings.display {
        case .notched:
            return Self.notchedScreen()
        case .pointer:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                ?? Self.notchedScreen()
        }
    }

    /// The screen with a notch (the built-in display, often not the primary screen),
    /// else the primary screen.
    private static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
}
