import AppKit
import Observation
import SwiftUI

enum PanelState {
    case closed
    case open
}

/// Single source of truth for the panel: `progress` (0 = notch, 1 = expanded) and state.
/// The hotkey (and, from Phase 5, the gesture) drive it; views only read it.
@Observable
final class PanelController {
    // Open with a slight Dynamic Island overshoot; close without bounce so it settles fast.
    static let openSpring = Spring(duration: 0.45, bounce: 0.2)
    static let closeSpring = Spring(duration: 0.35, bounce: 0)

    private(set) var progress: CGFloat = 0
    private(set) var state: PanelState = .closed
    private(set) var geometry: NotchGeometry

    private let panel: NotchPanel
    private let driver: SpringDriver

    init(panel: NotchPanel, geometry: NotchGeometry) {
        self.panel = panel
        self.geometry = geometry
        driver = SpringDriver(window: panel)
        driver.onChange = { [weak self] value in self?.progress = value }
    }

    func toggle() {
        if state == .open { close() } else { open() }
    }

    func open() {
        state = .open
        panel.ignoresMouseEvents = false
        driver.animate(to: 1, with: Self.openSpring)
    }

    func close() {
        state = .closed
        // Click-through from the moment it starts closing, not when the animation ends.
        panel.ignoresMouseEvents = true
        driver.animate(to: 0, with: Self.closeSpring)
    }

    #if DEBUG
    func debugJump(to value: CGFloat) {
        progress = value
    }
    #endif

    func updateGeometry(_ newGeometry: NotchGeometry) {
        guard newGeometry != geometry else { return }
        geometry = newGeometry
        panel.setFrame(newGeometry.panelFrame, display: true)
    }
}
