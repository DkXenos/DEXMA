import AppKit
import Observation
import SwiftUI

/// Latest trackpad contacts, fed only while the Settings window is open.
@Observable
final class TouchPreview {
    var touches: [TouchPoint] = []
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let permission: AccessibilityPermission
    let preview: TouchPreview
    let gesturesAvailable: () -> Bool
    let hotKeyWorking: () -> Bool
    let onRecordingChange: (Bool) -> Void
    let showWelcome: () -> Void

    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(combo: $settings.hotKey, onRecordingChange: onRecordingChange)
                }
                if !hotKeyWorking() {
                    Label("Another app is using this shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Picker("Show on", selection: $settings.display) {
                    Text("Built-in display (notch)").tag(DisplayChoice.notched)
                    Text("Display with the pointer").tag(DisplayChoice.pointer)
                }
                Toggle(isOn: $settings.escClosesPanel) {
                    Text("Esc closes the terminal")
                    Text("Except in full-screen programs like vim, less or htop.")
                }
                Toggle("Close when you click another app", isOn: $settings.closesOnFocusLoss)
                Toggle(isOn: $settings.hoverToPeek) {
                    Text("Peek when the pointer is over the notch")
                    Text("Click the peeking notch to open.")
                }
            }

            Section("Panel size") {
                LabeledContent("Width") {
                    Slider(value: $settings.panelWidth, in: AppSettings.panelWidthRange, step: 10)
                    Text("\(Int(settings.panelWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                LabeledContent("Height") {
                    Slider(value: $settings.panelHeight, in: AppSettings.panelHeightRange, step: 10)
                    Text("\(Int(settings.panelHeight)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }

            Section("Animation") {
                Slider(value: $settings.animationDuration, in: AppSettings.durationRange) {
                    Text("Speed")
                } minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Slow") }
                Slider(value: $settings.bounce, in: AppSettings.bounceRange) {
                    Text("Bounciness")
                } minimumValueLabel: { Text("None") } maximumValueLabel: { Text("Lots") }
                Slider(value: $settings.effectIntensity, in: AppSettings.effectIntensityRange) {
                    Text("Effect intensity")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Full") }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Text("Reduce Motion is on in System Settings, so animations are short, don't bounce, and skip the lens effect.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Trackpad gesture") {
                Toggle(isOn: $settings.gesturesEnabled) {
                    Text("Swipe down from the top edge to open")
                    Text("Two fingers. Swipe up to close.")
                }
                if settings.gesturesEnabled, !gesturesAvailable() {
                    Label("No multitouch trackpad found. Use the shortcut instead.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Slider(value: $settings.edgeZone, in: AppSettings.edgeZoneRange) {
                    Text("Start zone")
                } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Tall") }
                Slider(value: $settings.triggerDistance, in: AppSettings.triggerDistanceRange) {
                    Text("Swipe distance")
                } minimumValueLabel: { Text("Short") } maximumValueLabel: { Text("Long") }
                TrackpadPreview(preview: preview, edgeZone: settings.edgeZone)
                Toggle(isOn: $settings.invertTrackpadY) {
                    Text("Flip vertical direction")
                    Text("Only if your fingers show upside down in the preview above.")
                }
                LabeledContent {
                    if permission.isGranted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow in Accessibility…") { permission.requestAccess() }
                    }
                } label: {
                    Text("Stop pages scrolling during the swipe")
                    Text("Needs Accessibility. Starts by itself once allowed.")
                }
            }

            Section {
                Button("Show Welcome Screen…", action: showWelcome)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 760)
    }
}

/// Live view of the fingers on the trackpad, with the start zone shaded — for checking the
/// direction and tuning the zone.
struct TrackpadPreview: View {
    let preview: TouchPreview
    let edgeZone: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let pad = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: pad, cornerRadius: 10), with: .color(.secondary.opacity(0.15)))
                let zone = CGRect(x: 0, y: 0, width: size.width, height: size.height * edgeZone)
                context.fill(Path(zone), with: .color(.accentColor.opacity(0.25)))
                for touch in preview.touches {
                    // Trackpad y is 1 at the far (top) edge; the canvas grows downward.
                    let center = CGPoint(x: touch.x * size.width, y: (1 - touch.y) * size.height)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)),
                                 with: .color(.accentColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(height: 130)
            Text("Put two fingers in the shaded zone at the top, then swipe down.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let permission: AccessibilityPermission
    private let onVisibilityChange: (Bool) -> Void

    init(rootView: SettingsView, permission: AccessibilityPermission,
         onVisibilityChange: @escaping (Bool) -> Void) {
        self.permission = permission
        self.onVisibilityChange = onVisibilityChange
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "DEXMA Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        permission.startMonitoring()
        onVisibilityChange(true)
        NSApp.activate()  // An agent app must activate for its window to come to the front.
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        permission.stopMonitoring()
        onVisibilityChange(false)
    }
}
