import Observation

/// Keeps the panel's global shortcut registered for the combo in the settings: registers it
/// again when the combo changes, and switches it off while the Settings window records a new
/// one, so it can be typed as the new shortcut.
@Observable
final class HotKeyRegistrar {
    /// While the shortcut recorder listens, the current shortcut must not fire.
    var isPaused = false {
        didSet { update() }
    }

    private var hotKey: HotKey?
    private let action: () -> Void
    @ObservationIgnored private var combo: KeyCombo?
    @ObservationIgnored private var registeredCombo: KeyCombo?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// False if Carbon refused the combination (e.g. another app holds it exclusively).
    var isWorking: Bool {
        isPaused || hotKey?.isRegistered == true
    }

    func register(_ combo: KeyCombo) {
        self.combo = combo
        update()
    }

    /// No shortcut at all (its feature is switched off).
    func unregister() {
        combo = nil
        registeredCombo = nil
        hotKey = nil
    }

    private func update() {
        if isPaused {
            hotKey = nil
            registeredCombo = nil
            return
        }
        guard let combo, registeredCombo != combo else { return }
        hotKey = nil  // Unregister the old one first; Carbon refuses duplicates.
        hotKey = HotKey(keyCode: Int(combo.keyCode), modifiers: Int(combo.carbonModifiers),
                        action: action)
        registeredCombo = combo
    }
}
