import AppKit

/// Watches trackpad scroll events reaching DEXMA (a local event monitor: no permission
/// needed) and turns horizontal two-finger swipes over the open panel into tab swipes
/// (`TabSwipeTracker`). Everything else passes through untouched: vertical scrolling, mice,
/// and any scroll while the panel is closed.
final class TabSwipeMonitor {
    weak var target: TabSwipeTarget?
    var tuning = GestureTuning.standard

    private let panel: NSWindow
    private var monitor: Any?
    private var tracker = TabSwipeTracker()
    /// Where the fingers' gesture started (panel coordinates), for `canSwipeTabs`.
    private var startPoint: CGPoint?

    init(panel: NSWindow) {
        self.panel = panel
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let target, event.hasPreciseScrollingDeltas else { return event }
        guard target.acceptsTabSwipes || tracker.isSwiping else { return event }
        let phase = Self.phase(of: event)
        if phase == .began { startPoint = panelPoint(of: event) }
        let input = TabSwipeTracker.Input(
            phase: phase, isMomentum: !event.momentumPhase.isEmpty,
            dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, time: event.timestamp)
        let point = startPoint
        let output = tracker.handle(input, tuning: tuning, pageWidth: target.tabPageWidth) { direction in
            guard let point else { return false }
            return target.canSwipeTabs(at: point, direction: direction)
        }
        switch output {
        case .pass:
            return event
        case .swallow:
            return nil
        case .began(let delta):
            target.beginTabSwipe()
            target.updateTabSwipe(delta: delta)
            return nil
        case .changed(let delta):
            target.updateTabSwipe(delta: delta)
            return nil
        case .ended(let delta, let velocity):
            target.endTabSwipe(delta: delta, velocity: velocity)
            return nil
        }
    }

    /// The event's position in the panel (top-left origin), or nil if it isn't over it. From
    /// the event's global location, so events posted without a window work too.
    private func panelPoint(of event: NSEvent) -> CGPoint? {
        guard let global = event.cgEvent?.location else { return nil }
        // CGEvent locations are top-left based on the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: global.x, y: primaryHeight - global.y)
        let frame = panel.frame
        guard frame.contains(point) else { return nil }
        return CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    private static func phase(of event: NSEvent) -> TabSwipeTracker.Phase {
        let phase = event.phase
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.mayBegin) { return .mayBegin }
        return .none
    }
}
