import AppKit
import SwiftUI
import os

/// The composition root: builds every feature at launch, wires them together, applies the
/// settings live and opens DEXMA's windows. The only type that knows all the features.
final class AppCoordinator: WindowRouter {
    private static let logger = Logger(category: "App")

    let settings = AppSettings()
    private let accessibility = AccessibilityPermission()
    private let screenRecording = ScreenRecordingPermission()
    private let hover = HoverMonitor()
    private let scrollBlocker = ScrollBlocker()
    private lazy var geometryProvider = NotchGeometryProvider(settings: settings)
    private var notch: NotchViewModel?
    private var bender: ScreenBender?
    private var gestures: GestureEngine?
    private var hotKey: HotKeyRegistrar?
    private var captureHotKey: HotKeyRegistrar?
    private var capture: CaptureViewModel?
    private var captureOnboarding: CaptureOnboardingWindowController?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?

    func start() {
        guard let geometry = geometryProvider.makeGeometry() else { return }
        // Pre-warm: zsh starts now and outlives every open/close.
        let session = ShellSession(size: geometry.contentFrame.size)
        // Pre-warm: the Search card and its web view exist from launch (nothing loads yet).
        let search = WebTabViewModel(session: WebTab(configuration: .search, size: geometry.contentFrame.size))
        // Pre-warm: claude.ai loads now, so the Claude tab is instant (and stays signed in: the
        // website data store is the persistent default, shared with Search).
        let claude = WebTabViewModel(session: WebTab(configuration: .claude, size: geometry.contentFrame.size))
        let panel = NotchPanel(frame: geometry.panelFrame)
        let pager = ContentPagerView(size: geometry.contentFrame.size, cornerRadius: NotchGeometry.cardRadius)
        let runningDot = RunningDotView(frame: .zero)
        let urlField = URLEntryField(frame: .zero)
        let notch = NotchViewModel(panel: panel, session: session, search: search, claude: claude, pager: pager,
                                   runningDot: runningDot, urlField: urlField, geometry: geometry)
        notch.geometryForOpening = { [weak self] in self?.geometryProvider.makeGeometry() }
        // Pre-warm: the capture overlay (window, layers, hint) exists from launch, off screen.
        let capture = CaptureViewModel(panel: CaptureOverlayPanel(), claude: claude.session, router: self)
        capture.target = notch
        notch.capture = capture
        self.capture = capture

        let hostingView = NSHostingView(rootView: NotchContentView(viewModel: notch))
        hostingView.sizingOptions = []  // Fixed-size panel: SwiftUI must never resize it.
        // The panel overlaps the notch and menu bar on purpose; don't let AppKit safe-area
        // insets feed back into SwiftUI layout.
        hostingView.safeAreaRegions = []
        // The screen warp and Liquid Glass (while moving) sit under the SwiftUI content.
        let content = PanelContentView(frame: CGRect(origin: .zero, size: geometry.panelFrame.size))
        hostingView.frame = content.bounds
        hostingView.autoresizingMask = [.width, .height]
        content.addSubview(hostingView)
        content.addSubview(runningDot)  // Over the SwiftUI band.
        content.addSubview(urlField)
        let bender = ScreenBender(panel: panel, container: content,
                                  geometry: { [weak notch] in notch?.geometry ?? geometry })
        notch.bender = bender
        panel.contentView = content
        panel.acceptsMouseMovedEvents = true  // For the hover monitor while peeking.
        // Pre-warm: the panel stays on screen from launch. Closed, it hides under the notch.
        panel.orderFrontRegardless()
        self.notch = notch
        self.bender = bender

        let gestures = GestureEngine(target: notch)
        gestures.scrollGate = scrollBlocker.gate
        self.gestures = gestures
        // Without Accessibility this waits (polling) and starts by itself once it's granted.
        scrollBlocker.startWhenPermitted()

        hover.zone = { [weak notch] in notch?.hoverZone ?? .zero }
        hover.onChange = { [weak notch] inside in notch?.setHovering(inside) }
        hover.onMove = { [weak bender] point in bender?.pointerMoved(to: point) }

        // While capturing, the panel's shortcut cancels it (the panel would open under the overlay).
        hotKey = HotKeyRegistrar { [weak notch, weak capture] in
            if let capture, capture.isActive { capture.cancel() } else { notch?.toggle() }
        }
        captureHotKey = HotKeyRegistrar { [weak capture] in capture?.toggle() }
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()
        let menuBar = MenuBarViewModel(settings: settings, notch: notch, capture: capture, router: self)
        statusItem = StatusItemController(viewModel: menuBar)
        NSApp.mainMenu = MainMenu.make(viewModel: menuBar)
        Self.logger.notice(
            "Launched. Multitouch gestures: \(gestures.isRunning ? "on" : "unavailable", privacy: .public); scroll blocking: \(self.scrollBlocker.isActive ? "on" : "waiting for Accessibility", privacy: .public)")

        if !OnboardingRecord.isSeen {
            showWelcome()
        }
        // Compile the liquid effect's shaders now, so the first open doesn't hitch.
        LiquidMotionLayer<EmptyView>.precompile()
        DispatchQueue.main.async { notch.warmUpEffects() }
        #if DEBUG
        DebugHarness.runIfRequested(coordinator: self, panel: panel, notch: notch, session: session)
        #endif
    }

    /// Displays were added, removed or rearranged. Not while open: the panel moves (if it
    /// has to) the next time it opens.
    func screenParametersDidChange() {
        capture?.cancelDrawing()
        guard let notch, notch.state != .open, let geometry = geometryProvider.makeGeometry() else { return }
        notch.updateGeometry(geometry)
    }

    // MARK: Settings

    private func applySettings() {
        hotKey?.register(settings.hotKey)
        captureHotKey?.register(settings.captureHotKey)
        if let capture {
            capture.shortcut = settings.captureHotKey.display
            capture.startsNewChat = settings.captureNewChat
            capture.savesCopies = settings.captureSavesCopies
            capture.effectIntensity = settings.captureEffectiveIntensity
        }
        guard let notch, let gestures else { return }
        notch.escClosesPanel = settings.escClosesPanel
        notch.closesOnFocusLoss = settings.closesOnFocusLoss
        notch.animationDuration = settings.animationDuration
        notch.bounce = settings.bounce
        notch.effectIntensity = settings.effectIntensity
        notch.claude.session.pageZoom = settings.claudeZoom
        bender?.isWarpEnabled = settings.renderQuality.warps
        bender?.warpsAtRest = settings.renderQuality.warpsAtRest
        if let geometry = geometryProvider.makeGeometry() { notch.updateGeometry(geometry) }

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

    // MARK: Windows (WindowRouter)

    func showSettings() {
        if settingsWindow == nil {
            guard let gestures, let hotKey, let captureHotKey else { return }
            let viewModel = SettingsViewModel(settings: settings, accessibility: accessibility,
                                              screenRecording: screenRecording, gestures: gestures,
                                              hotKeys: [hotKey, captureHotKey], router: self)
            settingsWindow = SettingsWindowController(viewModel: viewModel)
        }
        settingsWindow?.show()
    }

    func showWelcome() {
        if onboarding == nil {
            let viewModel = OnboardingViewModel(settings: settings, accessibility: accessibility,
                                                screenRecording: screenRecording)
            onboarding = OnboardingWindowController(viewModel: viewModel)
        }
        onboarding?.show()
    }

    func showCaptureOnboarding() {
        let viewModel = CaptureOnboardingViewModel(permission: screenRecording,
                                                   shortcut: settings.captureHotKey.display)
        viewModel.onDrawNow = { [weak self] in self?.capture?.start() }
        captureOnboarding?.close()
        captureOnboarding = CaptureOnboardingWindowController(viewModel: viewModel)
        captureOnboarding?.show()
    }
}
