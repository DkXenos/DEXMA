import AppKit
import SwiftUI

struct OnboardingView: View {
    let permission: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let shortcut: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to DEXMA").font(.title2.bold())
                    Text("A terminal that lives in your notch.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Swipe down with two fingers from the very top edge of the trackpad",
                      systemImage: "hand.point.up.left")
                Label("…or press \(shortcut) from anywhere", systemImage: "keyboard")
                Label("Swipe up, press Esc, or press \(shortcut) again to close",
                      systemImage: "arrow.up.to.line")
                Label("DEXMA lives in the menu bar — quit and settings are there",
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
                        scrolling while you swipe the terminal open. DEXMA never reads or \
                        records your keystrokes.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !permission.isGranted {
                        Button("Open Accessibility Settings…") { permission.requestAccess() }
                        Text("Turn on DEXMA in the list. This updates as soon as you do — no restart needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Screen Recording (optional)").font(.headline)
                        Spacer()
                        if screenRecording.isGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    Text("""
                        Lets the notch bend and colour-split the screen around it as it opens, \
                        closes and when the pointer comes near. DEXMA only looks at the area \
                        around the notch, never saves it, and only while it's moving; macOS \
                        shows its recording indicator then.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !screenRecording.isGranted {
                        Button("Allow Screen Recording…") { screenRecording.requestAccess() }
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
    private let screenRecording: ScreenRecordingPermission
    private let onFinish: () -> Void

    init(permission: AccessibilityPermission, screenRecording: ScreenRecordingPermission,
         shortcut: String, onFinish: @escaping () -> Void) {
        self.permission = permission
        self.screenRecording = screenRecording
        self.onFinish = onFinish
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to DEXMA"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(
            permission: permission, screenRecording: screenRecording, shortcut: shortcut,
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
        screenRecording.startMonitoring()
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
        screenRecording.stopMonitoring()
    }
}
