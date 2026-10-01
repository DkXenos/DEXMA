import AppKit

/// The menu bar item — the only visible handle on an agent app, and the way to quit it.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()
        statusItem.button?.image = Self.makeIcon()
        statusItem.button?.setAccessibilityLabel("DEXMA")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let combo = app.settings.hotKey
        let toggle = item(app.isPanelOpen ? "Close Terminal" : "Open Terminal",
                          #selector(togglePanel), key: combo.menuKey)
        toggle.keyEquivalentModifierMask = combo.menuModifiers
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Welcome & Permissions…", #selector(openWelcome)))
        let login = item("Launch at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit DEXMA", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePanel() { app.togglePanel() }
    @objc private func openSettings() { app.showSettings(nil) }
    @objc private func openWelcome() { app.showOnboarding() }
    @objc private func toggleLoginItem() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// A screen outline with the notch at the top, as a template so it follows the menu bar.
    private static func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage() }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.set()
        let screen = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 12), xRadius: 3, yRadius: 3)
        screen.lineWidth = 1.5
        screen.stroke()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 9, width: 6, height: 4), xRadius: 1.5, yRadius: 1.5).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
