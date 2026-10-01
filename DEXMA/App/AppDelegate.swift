import AppKit
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DEXMA",
                                       category: "App")
    let settings = AppSettings()
    private var controller: PanelController?
    private var session: ShellSession?
    private var hotKey: HotKey?
    private var registeredCombo: KeyCombo?
    private var gestures: GestureEngine?
    private let hover = HoverMonitor()
    private let scrollBlocker = ScrollBlocker()
    let accessibility = AccessibilityPermission()
    let screenRecording = ScreenRecordingPermission()
    private var onboarding: OnboardingWindowController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?
    private let touchPreview = TouchPreview()
    /// While the Settings window records a new shortcut, the old one must not fire.
    var isRecordingShortcut = false {
        didSet { applyHotKey() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let geometry = makeGeometry() else { return }
        // Pre-warm: zsh starts now and outlives every open/close.
        let session = ShellSession(size: geometry.terminalFrame.size)
        let panel = NotchPanel(frame: geometry.panelFrame)
        let controller = PanelController(panel: panel, session: session, geometry: geometry)
        controller.geometryForOpening = { [weak self] in self?.makeGeometry() }

        let hostingView = NSHostingView(
            rootView: NotchContentView(controller: controller, session: session))
        hostingView.sizingOptions = []  // Fixed-size panel: SwiftUI must never resize it.
        // The panel overlaps the notch and menu bar on purpose; don't let AppKit safe-area
        // insets feed back into SwiftUI layout.
        hostingView.safeAreaRegions = []
        // The backdrop lens (Liquid Glass, while moving) sits under the SwiftUI content.
        let content = PanelContentView(frame: CGRect(origin: .zero, size: geometry.panelFrame.size))
        hostingView.frame = content.bounds
        hostingView.autoresizingMask = [.width, .height]
        content.addSubview(hostingView)
        controller.bender = ScreenBender(panel: panel, container: content,
                                         geometry: { [weak controller] in controller?.geometry ?? geometry })
        panel.contentView = content
        panel.acceptsMouseMovedEvents = true  // For the hover monitor while peeking.
        // Pre-warm: the panel stays on screen from launch. Closed, it hides under the notch.
        panel.orderFrontRegardless()
        self.controller = controller
        self.session = session

        let gestures = GestureEngine(controller: controller, session: session)
        gestures.scrollGate = scrollBlocker.gate
        self.gestures = gestures
        // Without Accessibility this waits (polling) and starts by itself once it's granted.
        scrollBlocker.startWhenPermitted()

        hover.zone = { [weak controller] in
            guard let controller else { return .zero }
            return Self.hoverZone(controller)
        }
        hover.onChange = { [weak controller] inside in controller?.setHovering(inside) }
        hover.onMove = { [weak controller] point in controller?.bender?.pointerMoved(to: point) }

        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()
        statusItem = StatusItemController(app: self)
        NSApp.mainMenu = MainMenu.make(target: self)
        Self.logger.notice(
            "Launched. Multitouch gestures: \(gestures.isRunning ? "on" : "unavailable", privacy: .public); scroll blocking: \(self.scrollBlocker.isActive ? "on" : "waiting for Accessibility", privacy: .public)")

        if !UserDefaults.standard.bool(forKey: "didShowOnboarding") {
            showOnboarding()
        }
        // Compile the liquid effect's shaders now, so the first open doesn't hitch.
        LiquidMotionLayer.precompile()
        DispatchQueue.main.async { controller.warmUpEffects() }
        #if DEBUG
        DebugSnapshot.runIfRequested(panel: panel, controller: controller, session: session)
        #endif
    }

    // MARK: Actions (menu bar item)

    func togglePanel() {
        controller?.toggle()
    }

    var isPanelOpen: Bool {
        controller?.state == .open
    }

    var isHotKeyWorking: Bool {
        isRecordingShortcut || hotKey?.isRegistered == true
    }

    var areGesturesRunning: Bool {
        gestures?.isRunning ?? false
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings, permission: accessibility, screenRecording: screenRecording,
                preview: touchPreview,
                gesturesAvailable: { [weak self] in self?.areGesturesRunning ?? false },
                hotKeyWorking: { [weak self] in self?.isHotKeyWorking ?? false },
                onRecordingChange: { [weak self] recording in self?.isRecordingShortcut = recording },
                showWelcome: { [weak self] in self?.showOnboarding() })
            settingsWindow = SettingsWindowController(
                rootView: view, permission: accessibility, screenRecording: screenRecording,
                onVisibilityChange: { [weak self] visible in self?.setTouchPreview(visible) })
        }
        settingsWindow?.show()
    }

    /// Touch frames only flow to the preview while Settings is on screen.
    private func setTouchPreview(_ enabled: Bool) {
        if !enabled { isRecordingShortcut = false }
        gestures?.onTouches = enabled ? { [weak self] touches in self?.touchPreview.touches = touches } : nil
        if !enabled { touchPreview.touches = [] }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: accessibility,
                                                    screenRecording: screenRecording,
                                                    shortcut: settings.hotKey.display) {
                UserDefaults.standard.set(true, forKey: "didShowOnboarding")
            }
        }
        onboarding?.show()
    }

    // MARK: Settings

    private func applySettings() {
        applyHotKey()
        guard let controller, let gestures else { return }
        controller.escClosesPanel = settings.escClosesPanel
        controller.closesOnFocusLoss = settings.closesOnFocusLoss
        controller.animationDuration = settings.animationDuration
        controller.bounce = settings.bounce
        controller.effectIntensity = settings.effectIntensity
        controller.bender?.isWarpEnabled = settings.screenWarp
        if let geometry = makeGeometry() { controller.updateGeometry(geometry) }

        gestures.parameters = GestureParameters(edgeZone: settings.edgeZone,
                                                triggerDistance: settings.triggerDistance)
        gestures.invertsY = settings.invertTrackpadY
        if settings.gesturesEnabled {
            gestures.start()  // No trackpad: stays off; the hotkey still works.
        } else {
            gestures.stop()
        }
        if settings.hoverToPeek { hover.start() } else { hover.stop() }
    }

    private func applyHotKey() {
        guard let controller else { return }
        if isRecordingShortcut {
            hotKey = nil
            registeredCombo = nil
            return
        }
        guard registeredCombo != settings.hotKey else { return }
        hotKey = nil  // Unregister the old one first; Carbon refuses duplicates.
        hotKey = HotKey(keyCode: Int(settings.hotKey.keyCode),
                        modifiers: Int(settings.hotKey.carbonModifiers)) { [weak controller] in
            controller?.toggle()
        }
        registeredCombo = settings.hotKey
    }

    // MARK: Screens

    private func openingScreen() -> NSScreen? {
        switch settings.display {
        case .notched:
            return NotchGeometry.notchedScreen()
        case .pointer:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                ?? NotchGeometry.notchedScreen()
        }
    }

    private func makeGeometry() -> NotchGeometry? {
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

    /// The notch plus a little slack; while peeking, the swollen shape too, so the pointer
    /// doesn't flicker in and out at its edge.
    private static func hoverZone(_ controller: PanelController) -> CGRect {
        let notch = controller.geometry.notchRect
        let grow: CGFloat = controller.state == .peek ? 24 : 6
        return CGRect(x: notch.minX - grow, y: notch.minY - grow,
                      width: notch.width + 2 * grow, height: notch.height + grow + 1)
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let controller, controller.state != .open, let geometry = makeGeometry() else { return }
        controller.updateGeometry(geometry)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
