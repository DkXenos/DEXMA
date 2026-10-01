import AppKit
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
        switch ShortcutInput(keyCode: event.keyCode, modifiers: event.modifierFlags,
                             characters: event.charactersIgnoringModifiers) {
        case .cancel:
            stop()
        case .needsModifier:
            hint = "Add ⌘, ⌥ or ⌃"
        case .shortcut(let newCombo):
            combo = newCombo
            stop()
        }
    }
}
