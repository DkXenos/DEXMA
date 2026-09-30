import AppKit

/// Reports when the pointer enters or leaves a screen rect (the notch), for the peek state.
/// Mouse-moved monitors need no permission. Global covers other apps' windows; local covers
/// our own panel once it takes mouse events while peeking.
final class HoverMonitor {
    /// Hot zone in global AppKit coordinates, re-read on every move (it follows the state).
    var zone: () -> CGRect = { .zero }
    var onChange: ((Bool) -> Void)?

    private var monitors: [Any] = []
    private var isInside = false

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }  // Delivered on the main thread.
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.check()
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if isInside {
            isInside = false
            onChange?(false)
        }
    }

    private func check() {
        let inside = zone().contains(NSEvent.mouseLocation)
        guard inside != isInside else { return }
        isInside = inside
        onChange?(inside)
    }
}
