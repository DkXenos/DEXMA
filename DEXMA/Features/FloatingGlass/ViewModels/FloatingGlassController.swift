import AppKit
import Observation
import SwiftUI

/// Presents a `FloatingGlassPanel` like Spotlight: on the screen with the pointer, its shapes
/// materializing with a slight scale (0.96 → 1) on a spring, the buttons growing out of the main
/// shape a moment later; dismissed by Esc, a click outside or losing the keyboard, with the
/// keyboard going back to the app the user was in. Reusable: knows nothing of its content.
/// The views read `isShown`, `showsAccessories` and `scale`; every change of them is animated
/// here (SwiftUI transitions, the system's glass transitions).
@Observable
final class FloatingGlassController {
    /// The shapes are there (inserted with the glass's materialize transition).
    private(set) var isShown = false
    /// The round buttons beside the main shape (inserted a moment later, so they morph out of it).
    private(set) var showsAccessories = false
    /// The shapes' scale: 1 shown; 0.96 while hidden, so they appear growing from it.
    private(set) var scale: CGFloat = 0.96
    private(set) var layout: GlassLayout
    /// The panel is on screen (also while its shapes are going away).
    private(set) var isOnScreen = false

    let panel = FloatingGlassPanel()
    /// Shown or about to be: the panel is up and wasn't dismissed since.
    @ObservationIgnored private(set) var isPresented = false
    @ObservationIgnored var onDidDismiss: (() -> Void)?
    /// Whether losing the keyboard to `window` keeps the glass up (e.g. its own sign-in popup).
    @ObservationIgnored var keepsShownWhenKey: ((NSWindow) -> Bool)?
    @ObservationIgnored private let buttonCount: Int
    @ObservationIgnored private let focus = FocusHandoff()
    /// Each presentation's number: a dismissal's completion from an earlier one does nothing.
    @ObservationIgnored private var generation = 0

    init(buttonCount: Int) {
        self.buttonCount = buttonCount
        let screen = NSScreen.screens.first ?? NSScreen()
        layout = GlassLayout(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, buttonCount: buttonCount)
        panel.setFrame(layout.windowFrame, display: false)
        panel.onResignKey = { [weak self] in self?.didResignKey() }
    }

    /// The system's Reduce Motion: fades only (no scale, no morphs).
    var reduceMotion: Bool {
        #if DEBUG
        if let debugReduceMotion { return debugReduceMotion }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The appear/disappear spring, ~0.3 s like Spotlight; Reduce Motion: a short fade.
    var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: 0.3, bounce: 0.12)
    }

    /// Puts the panel up on `screen` (default: the one with the pointer) and takes the keyboard;
    /// `focus` then puts it where it belongs (a field). Already up: just the keyboard.
    func present(on screen: NSScreen? = nil, focus focusContent: () -> Void) {
        let screen = screen ?? Self.screenWithPointer()
        generation += 1
        if !isPresented {
            isPresented = true
            focus.rememberFrontmostApp()
            let fresh = GlassLayout(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                    buttonCount: buttonCount)
            if fresh != layout { layout = fresh }
            // Moves while nothing is drawn (no shapes yet).
            if panel.frame != fresh.windowFrame { panel.setFrame(fresh.windowFrame, display: false) }
            panel.allowsKey = true
            panel.orderFrontRegardless()
            isOnScreen = true
            withAnimation(spring) {
                isShown = true
                scale = 1
            }
            let id = generation
            // The buttons a beat later, so they grow out of the main shape (glassEffectID morph).
            let delay = reduceMotion ? 0 : 0.07
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, id == self.generation, self.isPresented else { return }
                withAnimation(self.spring) { self.showsAccessories = true }
            }
        }
        panel.makeKey()
        focusContent()
    }

    /// The shapes go (materializing out), then the panel orders out. `returnsFocus` false: the
    /// keyboard already went where the user clicked, or to another DEXMA window.
    func dismiss(returnsFocus: Bool = true) {
        guard isPresented else { return }
        isPresented = false
        generation += 1
        let id = generation
        panel.allowsKey = false
        withAnimation(spring, completionCriteria: .removed) {
            isShown = false
            showsAccessories = false
            scale = reduceMotion ? 1 : 0.96
        } completion: { [weak self] in
            guard let self, id == self.generation else { return }
            self.panel.orderOut(nil)
            self.isOnScreen = false
            self.onDidDismiss?()
        }
        // The keyboard goes back on the next run-loop turn (a few ms of IPC), not in the pass that
        // starts the animation; not at all if it's been presented again meanwhile.
        DispatchQueue.main.async { [weak self] in
            guard let self, id == self.generation else { return }
            if returnsFocus { self.focus.returnFocus(from: self.panel) } else { self.focus.forget() }
        }
    }

    /// Clicked into another app (or another DEXMA window took the keyboard): get out of the way.
    private func didResignKey() {
        guard isPresented else { return }
        // The new key window is known once AppKit has finished the switch.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented, !self.panel.isKeyWindow else { return }
            if let key = NSApp.keyWindow, self.keepsShownWhenKey?(key) == true { return }
            self.dismiss(returnsFocus: false)
        }
    }

    /// Launch: the shapes are built and drawn once, invisibly (the window at zero opacity), so the
    /// first real present doesn't pay for setting up the glass.
    func warmUp() {
        guard !isPresented, !isOnScreen else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            isShown = true
            showsAccessories = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isPresented else { return }
            withTransaction(still) {
                self.isShown = false
                self.showsAccessories = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                if !self.isPresented { self.panel.orderOut(nil) }
                self.panel.alphaValue = 1
            }
        }
    }

    /// The layout for `screen` (the capture's landing, before the panel moves there).
    func layout(on screen: NSScreen) -> GlassLayout {
        GlassLayout(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, buttonCount: buttonCount)
    }

    static func screenWithPointer() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.screens.first ?? NSScreen()
    }

    #if DEBUG
    @ObservationIgnored var debugReduceMotion: Bool?
    #endif
}
