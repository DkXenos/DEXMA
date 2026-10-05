import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        @Bindable var settings = viewModel.settings
        let launchesAtLogin = viewModel.launchesAtLogin

        Form {
            Section {
                LabeledContent("Width") {
                    Slider(value: $settings.panelWidth, in: AppSettings.panelWidthRange, step: 10)
                    Text("\(Int(settings.panelWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                LabeledContent("Height") {
                    Slider(value: $settings.panelHeight, in: AppSettings.panelHeightRange, step: 10)
                    Text("\(Int(settings.panelHeight)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("Open panel size")
            } footer: {
                Text("How big the notch grows when it opens. Changes apply right away, even while it's open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Look & performance") {
                Slider(value: $settings.effectIntensity, in: AppSettings.effectIntensityRange) {
                    Text("Glass effect strength")
                    Text("The liquid lens as the notch opens and closes, and on the tabs and buttons under the pointer.")
                } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Full") }
                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: Binding(get: { Double(settings.renderQuality.rawValue) },
                                              set: { settings.renderQuality = RenderQuality(rawValue: Int($0.rounded())) ?? .quality }),
                               in: 0...Double(RenderQuality.allCases.count - 1), step: 1) {
                            EmptyView()
                        } minimumValueLabel: { Text("Performance") } maximumValueLabel: { Text("Quality") }
                        Text("\(settings.renderQuality.title): \(settings.renderQuality.summary)")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    Text("Screen warp")
                    Text("Bends what's behind the notch, like the screen around the iPhone's Camera Control.")
                }
                if settings.renderQuality.warps {
                    LabeledContent {
                        if viewModel.isScreenRecordingGranted {
                            Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Allow Screen Recording…", action: viewModel.requestScreenRecording)
                        }
                    } label: {
                        Text("Screen Recording")
                        Text("DEXMA only looks at the area around the notch and never saves it. Without it, a Liquid Glass edge bends the screen instead (macOS 26).")
                    }
                }
                if viewModel.reducesMotion {
                    Text("Reduce Motion is on in System Settings, so animations are short, don't bounce, and skip the lens effect.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("General") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(combo: $settings.hotKey, onRecordingChange: viewModel.setRecordingShortcut)
                }
                if !viewModel.isHotKeyWorking {
                    Label("Another app is using this shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle("Launch at login", isOn: Binding(get: { launchesAtLogin },
                                                        set: { viewModel.setLaunchesAtLogin($0) }))
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

            Section("Animation") {
                Slider(value: $settings.animationDuration, in: AppSettings.durationRange) {
                    Text("Speed")
                } minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Slow") }
                Slider(value: $settings.bounce, in: AppSettings.bounceRange) {
                    Text("Bounciness")
                } minimumValueLabel: { Text("None") } maximumValueLabel: { Text("Lots") }
            }

            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(combo: $settings.captureHotKey, defaultCombo: .defaultCaptureCombo,
                                     onRecordingChange: viewModel.setRecordingShortcut)
                }
                if viewModel.hotKeysClash {
                    Label("This is also the panel's shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if !viewModel.isCaptureHotKeyWorking {
                    Label("Another app is using this shortcut. Pick a different one.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle(isOn: $settings.captureNewChat) {
                    Text("Start a new chat for each capture")
                    Text("Otherwise the capture goes into the chat that's open in the Claude tab.")
                }
                Toggle(isOn: $settings.captureSavesCopies) {
                    Text("Also save captures to ~/Pictures/DEXMA")
                    Text("Otherwise captures stay in memory and are gone once they're in Claude.")
                }
                Toggle("Effects follow the glass effect strength", isOn: $settings.captureEffectsFollowGlass)
                if !settings.captureEffectsFollowGlass {
                    Slider(value: $settings.captureEffectIntensity, in: AppSettings.effectIntensityRange) {
                        Text("Capture effects")
                        Text("The glow around the screen's edges and the shimmer along what you draw.")
                    } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Full") }
                }
                LabeledContent {
                    if viewModel.isScreenRecordingGranted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow Screen Recording…", action: viewModel.requestScreenRecording)
                    }
                } label: {
                    Text("Screen Recording")
                    Text("Needed to see what you draw around. One still picture per capture, DEXMA's windows left out.")
                }
            } header: {
                Text("Draw to ask Claude")
            } footer: {
                Text("Press the shortcut or the pencil in the notch, draw around anything (or click a window), and it lands in Claude's message box.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.claudeInGlass) {
                    Text("Claude in floating glass (preview)")
                    Text("A Spotlight-style Liquid Glass window instead of the notch: the Claude tab and Draw to ask open it.")
                }
                if settings.claudeInGlass {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(combo: $settings.glassHotKey, defaultCombo: .defaultGlassCombo,
                                         onRecordingChange: viewModel.setRecordingShortcut)
                    }
                    if let clash = viewModel.glassHotKeyClash {
                        Label("This is also \(clash) shortcut. Pick a different one.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if !viewModel.isGlassHotKeyWorking {
                        Label("Another app is using this shortcut. Pick a different one.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Toggle(isOn: $settings.claudeSeeThrough) {
                        Text("See-through Claude page")
                        Text("The conversation shows the glass through it. Off: claude.ai's own dark background inside the glass.")
                    }
                }
                LabeledContent("Page zoom") {
                    Slider(value: $settings.claudeZoom, in: AppSettings.claudeZoomRange, step: 0.05)
                    Text("\(Int((settings.claudeZoom * 100).rounded())) %").monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("Claude tab")
            }

            Section {
                Toggle(isOn: $settings.devicePeekOnConnect) {
                    Text("Show battery peek on connect")
                    Text("The notch shows the levels for a few seconds when your Buds connect. Click it to open the Devices tab.")
                }
                Toggle(isOn: $settings.deviceLowBatteryAlerts) {
                    Text("Low battery alerts")
                    Text("The same peek in red when a bud drops to 20 %, and again at 10 %.")
                }
                Toggle(isOn: $settings.devicePeekInFullScreen) {
                    Text("Show in full screen")
                    Text("Also peek while a full-screen app is in front.")
                }
                LabeledContent {
                    if viewModel.isBluetoothGranted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(viewModel.isBluetoothDenied ? "Allow in Bluetooth Settings…" : "Open Bluetooth Settings…",
                               action: viewModel.openBluetoothSettings)
                    }
                } label: {
                    Text("Bluetooth")
                    Text("Needed to read the Buds' battery. Only while they're connected; nothing is ever sent to them.")
                }
                ForEach(viewModel.knownDevices) { device in
                    LabeledContent {
                        Button("Forget") { viewModel.forget(device) }
                    } label: {
                        Text(device.name)
                        Text([device.model, viewModel.deviceStatus(device)].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("Forget removes a device and its last levels; it comes back the next time it connects.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Trackpad gesture") {
                Toggle(isOn: $settings.gesturesEnabled) {
                    Text("Swipe down from the top edge to open")
                    Text("Two fingers. Swipe up to close.")
                }
                if settings.gesturesEnabled, !viewModel.areGesturesAvailable {
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
                TrackpadPreview(viewModel: viewModel.trackpadPreview, edgeZone: settings.edgeZone)
                Toggle(isOn: $settings.invertTrackpadY) {
                    Text("Flip vertical direction")
                    Text("Only if your fingers show upside down in the preview above.")
                }
                LabeledContent {
                    if viewModel.isAccessibilityGranted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow in Accessibility…", action: viewModel.requestAccessibility)
                    }
                } label: {
                    Text("Stop pages scrolling during the swipe")
                    Text("Needs Accessibility. Starts by itself once allowed.")
                }
            }

            Section {
                Button("Show Welcome Screen…", action: viewModel.showWelcome)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 760)
    }
}
