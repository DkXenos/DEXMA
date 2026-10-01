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

            Section("Claude tab") {
                LabeledContent("Page zoom") {
                    Slider(value: $settings.claudeZoom, in: AppSettings.claudeZoomRange, step: 0.05)
                    Text("\(Int((settings.claudeZoom * 100).rounded())) %").monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
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
