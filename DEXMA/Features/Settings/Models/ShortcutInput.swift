import AppKit
import Carbon.HIToolbox

/// What a key press means to the shortcut recorder: cancel (Esc), not usable as a global
/// shortcut (it needs ⌘, ⌥ or ⌃, unless it's a function key), or the new shortcut. Pure, so
/// it's unit-tested without real key events.
nonisolated enum ShortcutInput: Equatable {
    case cancel
    case needsModifier
    case shortcut(KeyCombo)

    /// `characters`: the event's `charactersIgnoringModifiers`.
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        if keyCode == UInt16(kVK_Escape), flags.isEmpty {
            self = .cancel
            return
        }
        let isFunctionKey = Self.functionKeys[Int(keyCode)] != nil
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else {
            self = .needsModifier
            return
        }
        self = .shortcut(KeyCombo(keyCode: UInt32(keyCode), carbonModifiers: Self.carbon(flags),
                                  display: Self.symbols(flags) + Self.keyName(keyCode, characters),
                                  menuKey: isFunctionKey ? "" : (characters?.lowercased() ?? "")))
    }

    private static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        // Apple's canonical order.
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←",
        kVK_RightArrow: "→", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static func keyName(_ keyCode: UInt16, _ characters: String?) -> String {
        let code = Int(keyCode)
        if let name = functionKeys[code] ?? namedKeys[code] { return name }
        return characters?.uppercased() ?? "?"
    }
}
