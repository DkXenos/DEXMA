import AppKit
import Carbon.HIToolbox
import Testing
@testable import DEXMA

/// The shortcut recorder's key handling, without real key events.
struct ShortcutInputTests {
    @Test func escapeCancels() {
        #expect(ShortcutInput(keyCode: UInt16(kVK_Escape), modifiers: [], characters: "\u{1b}") == .cancel)
    }

    @Test func plainKeysNeedCommandOptionOrControl() {
        #expect(ShortcutInput(keyCode: UInt16(kVK_ANSI_K), modifiers: [], characters: "k") == .needsModifier)
        #expect(ShortcutInput(keyCode: UInt16(kVK_ANSI_K), modifiers: [.shift], characters: "K") == .needsModifier)
    }

    @Test func optionGraveIsTheDefaultShortcut() {
        #expect(ShortcutInput(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.option], characters: "`")
            == .shortcut(.defaultCombo))
    }

    @Test func modifiersShowInApplesOrder() {
        let input = ShortcutInput(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control],
                                  characters: "k")
        guard case .shortcut(let combo) = input else { Issue.record("no shortcut"); return }
        #expect(combo.display == "⌃⌥⇧⌘K")
        #expect(combo.menuKey == "k")
        #expect(combo.menuModifiers == [.command, .option, .control, .shift])
    }

    @Test func functionKeysWorkAloneAndHaveNoMenuKey() {
        // Real F-key events carry the `.function` flag; it isn't a modifier for shortcuts.
        let input = ShortcutInput(keyCode: UInt16(kVK_F5), modifiers: [.function], characters: nil)
        guard case .shortcut(let combo) = input else { Issue.record("no shortcut"); return }
        #expect(combo.display == "F5")
        #expect(combo.menuKey == "")
        #expect(combo.carbonModifiers == 0)
    }

    @Test func namedKeysShowAsWordsOrSymbols() {
        let input = ShortcutInput(keyCode: UInt16(kVK_Space), modifiers: [.command], characters: " ")
        guard case .shortcut(let combo) = input else { Issue.record("no shortcut"); return }
        #expect(combo.display == "⌘Space")
    }
}
