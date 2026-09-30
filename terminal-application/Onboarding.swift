import AppKit
import SwiftUI

struct OnboardingView: View {
    let permission: AccessibilityPermission
    let shortcut: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to NotchTerm").font(.title2.bold())
                    Text("A terminal that lives in your notch.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Swipe down with two fingers from the very top edge of the trackpad",
                      systemImage: "hand.point.up.left")
                Label("…or press \(shortcut) from anywhere", systemImage: "keyboard")
                Label("Swipe up, press Esc, or press \(shortcut) again to close",
                      systemImage: "arrow.up.to.line")
                Label("NotchTerm lives in the menu bar — quit and settings are there",
                      systemImage: "menubar.rectangle")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Accessibility").font(.headline)
                        Spacer()
                        if permission.isGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not granted", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("""
                        Needed for one thing: stopping the window under your cursor from \
                        scrolling while you swipe the terminal open. NotchTerm never reads or \
                        records your keystrokes.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !permission.isGranted {
                        Button("Open Accessibility Settings…") { permission.requestAccess() }
                        Text("Turn on NotchTerm in the list. This updates as soon as you do — no restart needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            HStack {
                Text("Without it everything still works; the page under the cursor may scroll a little as you swipe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let permission: AccessibilityPermission
    private let onFinish: () -> Void

    init(permission: AccessibilityPermission, shortcut: String, onFinish: @escaping () -> Void) {
        self.permission = permission
        self.onFinish = onFinish
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to NotchTerm"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(
            permission: permission, shortcut: shortcut,
            onDone: { [weak self] in
                self?.onFinish()
                self?.window?.close()
            }))
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        permission.startMonitoring()
        NSApp.activate()  // An agent app must activate for its window to come to the front.
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // Only the user dismissing it counts as "seen" — not the app quitting with it open.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onFinish()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        permission.stopMonitoring()
    }
}
