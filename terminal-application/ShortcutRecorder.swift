import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination. Esc cancels. While recording, the current global
/// shortcut is switched off (`onRecordingChange`) so it can be typed as the new one.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Type a shortcut…" : combo.display) {
                if isRecording { stop() } else { start() }
            }
            .frame(minWidth: 130)
            if isRecording {
                Text(hint ?? "Esc cancels").font(.caption).foregroundStyle(.secondary)
            } else if combo != .defaultCombo {
                Button("Reset") { combo = .defaultCombo }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }  // Local monitors run on the main thread.
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            stop()
            return
        }
        let isFunctionKey = Self.functionKeys[Int(event.keyCode)] != nil
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else {
            hint = "Add ⌘, ⌥ or ⌃"
            return
        }
        combo = KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: Self.carbon(flags),
                         display: Self.symbols(flags) + Self.keyName(event),
                         menuKey: isFunctionKey ? "" : (event.charactersIgnoringModifiers?.lowercased() ?? ""))
        stop()
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

    private static func keyName(_ event: NSEvent) -> String {
        let code = Int(event.keyCode)
        if let name = functionKeys[code] ?? namedKeys[code] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
