import AppKit
import Carbon.HIToolbox

/// A global shortcut as Carbon wants it, plus how to show it.
nonisolated struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String
    /// For showing the shortcut next to a menu item ("" if it has no character).
    var menuKey: String

    static let defaultCombo = KeyCombo(keyCode: UInt32(kVK_ANSI_Grave),
                                       carbonModifiers: UInt32(optionKey), display: "⌥`",
                                       menuKey: "`")

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
