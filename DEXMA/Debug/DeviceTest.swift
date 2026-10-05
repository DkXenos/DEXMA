#if DEBUG
import AppKit
import CoreBluetooth

/// Debug-only: `DEXMA -devicetest <dir>` checks the Devices tab and the connect peek with a
/// mock pair of Buds driven through the `DeviceStore` (the real path minus Bluetooth), starts
/// the real Buds monitor once (launch check), writes PNGs of the panel window, prints a report
/// and quits. Removes the mock device and restores the settings it touched.
enum DeviceTest {
    private static let id = "mock:devicetest"

    /// Frames while the pill moved. Gaps over 100 ms are the display link resting between the
    /// grow and the collapse (or a screenshot taken at rest), not late frames.
    private static func pacing(_ probe: FramePacingProbe, _ name: String, _ report: (Bool, String) -> Void) {
        let first = probe.stamps.first ?? 0
        var lateAt: [String] = []
        var intervals: [Double] = []
        for index in probe.stamps.indices.dropFirst() {
            let gap: Double = probe.stamps[index] - probe.stamps[index - 1]
            guard gap < 0.1 else { continue }
            intervals.append(gap)
            if gap > 1.5 / 120 {
                lateAt.append(String(format: "%.0f ms in (%.1f ms)", (probe.stamps[index - 1] - first) * 1000, gap * 1000))
            }
        }
        report(lateAt.count <= 1, String(format: "pacing, %@: %d frames, %d late (>12.5 ms)%@, step p95 %.2f ms, run-loop pass p95 %.2f ms",
                                         name, intervals.count, lateAt.count,
                                         lateAt.isEmpty ? "" : " at " + lateAt.joined(separator: ", "),
                                         FramePacingProbe.percentile(probe.stepTimes, 0.95),
                                         FramePacingProbe.percentile(probe.passes, 0.95)))
    }

    static func run(panel: NotchPanel, notch: NotchViewModel, startMonitor: @escaping () -> Bool, dir: URL) {
        Task { @MainActor in
            notch.closesOnFocusLoss = false
            let devices = notch.devices
            let store = devices.store
            var failures = 0
            @MainActor func report(_ ok: Bool, _ text: String) {
                if !ok { failures += 1 }
                print("[devices] \(ok ? "OK  " : "FAIL") \(text)")
            }
            @MainActor func shot(_ name: String) {
                if let image = DebugImages.window(panel) { DebugImages.write(image, dir, name) }
            }
            @MainActor func reading(_ left: Int?, _ right: Int?, _ caseLevel: Int?, charging: Bool = false) -> BatteryReading {
                BatteryReading(components: [ComponentReading(role: .left, level: left, isCharging: charging),
                                            ComponentReading(role: .right, level: right, isCharging: charging),
                                            ComponentReading(role: .case, level: caseLevel, isCharging: false)])
            }
            @MainActor func waitForActivityToGo(_ seconds: Double = 6) async -> Bool {
                let start = CACurrentMediaTime()
                while notch.activity != nil, CACurrentMediaTime() - start < seconds {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                return notch.activity == nil && notch.activityAmount == 0
            }

            // Launch check of the real monitor (asks for Bluetooth the first time).
            let running = startMonitor()
            print("[devices] Bluetooth authorization \(CBManager.authorization.rawValue) (3 = allowed); Buds monitor \(running ? "running" : "not running")")
            let fullScreen = FullScreenSpace.isActive(onScreenWithFrame: notch.geometry.screenFrame)
            print("[devices] full-screen app in front on the notch's display: \(fullScreen)")
            devices.peeksInFullScreen = true  // So the peek shows whatever is in front during the test.
            devices.peeksOnConnect = true
            devices.lowBatteryAlerts = true
            store.forget(id)
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            try? await Task.sleep(for: .milliseconds(600))

            // 0. Baseline: the existing hover peek (same motion path), twice, on this Mac now.
            for round in 1...2 {
                let baseline = FramePacingProbe(driver: notch.debugDriver)
                baseline.startSeries()
                notch.setHovering(true)
                try? await Task.sleep(for: .milliseconds(900))
                notch.setHovering(false)
                _ = await notch.waitForRest()
                try? await Task.sleep(for: .milliseconds(300))
                pacing(baseline, "baseline hover peek \(round) (in + out)", { _, text in print("[devices] info \(text)") })
                baseline.stop()
            }

            // 1. Connect: the first reading grows the pill, without taking the keyboard.
            let probe = FramePacingProbe(driver: notch.debugDriver)
            probe.startSeries()
            store.deviceConnected(id: id, name: "Mewo", kind: .buds, source: .mock, model: "Galaxy Buds3 Pro")
            report(notch.activity == nil, "connect alone (no reading yet): no peek")
            store.apply(reading(80, 75, 40), to: id)
            report(notch.activity?.text == "L 80% · R 75% · Case 40%" && notch.activity?.isAlert == false,
                   "first reading → peek \"\(notch.activity?.text ?? "-")\"")
            try? await Task.sleep(for: .milliseconds(900))
            let layout = notch.activityLayout
            let shape = notch.silhouette.shape
            report(abs(notch.activityAmount - 1) < 0.01 && layout != nil
                   && abs(shape.width - (layout?.size.width ?? 0)) < 0.5 && abs(shape.height - (layout?.size.height ?? 0)) < 0.5,
                   String(format: "pill out: amount %.3f, silhouette %.1f × %.1f (pill %.0f × %.0f, notch %.0f × %.0f)",
                          notch.activityAmount, shape.width, shape.height, layout?.size.width ?? 0, layout?.size.height ?? 0,
                          notch.geometry.notchRect.width, notch.geometry.notchRect.height))
            report(!panel.isKeyWindow && NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost
                   && notch.state == .closed && panel.ignoresMouseEvents,
                   "no focus taken: key \(panel.isKeyWindow), frontmost unchanged, state \(notch.state), click-through \(panel.ignoresMouseEvents)")
            shot("1-peek")
            let hover = notch.hoverZone
            report(hover.contains(CGPoint(x: notch.geometry.notchRect.minX - 50, y: notch.geometry.screenFrame.maxY - 30)),
                   "pointer zone covers the pill's wings")
            // A reading while it's out: the text follows.
            store.apply(reading(79, 75, 40), to: id)
            report(notch.activity?.text == "L 79% · R 75% · Case 40%", "update while out → \"\(notch.activity?.text ?? "-")\"")
            let gone = await waitForActivityToGo()
            report(gone, String(format: "collapsed by itself after ~%.0f s", NotchViewModel.activityDuration))
            pacing(probe, "first peek (grow + collapse)", report)
            probe.stop()

            // 2. Low battery: red peek at 20 %, again at 10 %, not in between.
            let second = FramePacingProbe(driver: notch.debugDriver)
            second.startSeries()
            store.apply(reading(20, 75, nil), to: id)
            report(notch.activity?.isAlert == true && notch.activity?.parts.first?.isLow == true,
                   "left at 20 % → red peek \"\(notch.activity?.text ?? "-")\"")
            try? await Task.sleep(for: .milliseconds(700))
            shot("2-low")
            report(store.device(id)?.component(.case)?.level == 40, "case unknown in that reading → kept at 40")
            _ = await waitForActivityToGo()
            pacing(second, "low battery peek (grow + collapse)", report)
            second.stop()
            store.apply(reading(15, 75, nil), to: id)
            report(notch.activity == nil, "15 % → no new alert")
            store.apply(reading(10, 75, nil), to: id)
            report(notch.activity?.isAlert == true, "10 % → red peek again")

            // 3. A click on the pill opens the panel on the Devices tab.
            try? await Task.sleep(for: .milliseconds(400))
            notch.setHovering(true)
            let pill = notch.geometry.activityRect(size: notch.activityLayout?.size ?? .zero)
            let location = panel.convertPoint(fromScreen: CGPoint(x: pill.minX + 20, y: pill.midY))
            if let click = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                              clickCount: 1, pressure: 1) {
                panel.sendEvent(click)
            }
            _ = await notch.waitForRest()
            while notch.debugTabDriver.isAnimating { try? await Task.sleep(for: .milliseconds(20)) }
            try? await Task.sleep(for: .milliseconds(800))
            report(notch.state == .open && notch.tab == .devices && notch.activity == nil,
                   "click on the pill → open on \(notch.tab), pill gone \(notch.activity == nil)")
            report(devices.bandSummary == "Mewo  L 10%  R 75%  Case 40%", "band summary \"\(devices.bandSummary)\"")
            shot("3-devices-tab")
            let snapshot = notch.devicesPage.motionSnapshot()
            let card = notch.geometry.contentFrame
            report(snapshot.map { abs($0.size.width - card.width) < 1 && abs($0.size.height - card.height) < 1 } ?? false,
                   "page picture for the liquid effect: \(snapshot.map { "\(Int($0.size.width)) × \(Int($0.size.height)) @\(Int($0.scale))x" } ?? "none")")
            if let image = snapshot?.image, let over = DebugImages.overBlack(image) { DebugImages.write(over, dir, "3-devices-snapshot") }

            // Controls: what the card shows is the system's (read-only check; volume is written
            // back at its current value only, so nothing changes for the user).
            let controls = notch.devicesPage.debugControls
            let systemBrightness = DisplayBrightness.level()
            report(controls.brightness != nil && systemBrightness.map { abs(Double($0) - (controls.brightness ?? -1)) < 0.01 } == true,
                   String(format: "brightness slider %.2f (system %.2f)", controls.brightness ?? -1, systemBrightness ?? -1))
            let before = controls.volume
            let start = CACurrentMediaTime()
            if let before { controls.setVolume(before) }
            let setTime = (CACurrentMediaTime() - start) * 1000
            report(before != nil && controls.canSetVolume && controls.volume.map { abs($0 - (before ?? -1)) < 0.01 } == true,
                   String(format: "volume slider %.2f, muted %@, settable %@; write-back %.2f ms", controls.volume ?? -1,
                          controls.isMuted ? "yes" : "no", controls.canSetVolume ? "yes" : "no", setTime))
            let readStart = CACurrentMediaTime()
            controls.refresh()
            print(String(format: "[devices]   controls refresh (brightness + volume read): %.2f ms", (CACurrentMediaTime() - readStart) * 1000))

            // 4. Keys: ⌘1 then ⌘4, ⌃Tab wraps to the terminal.
            @MainActor func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent? {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                 windowNumber: panel.windowNumber, context: nil, characters: characters,
                                 charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            }
            if let event = key("1", 18, .command) { _ = panel.performKeyEquivalent(with: event) }
            let afterOne = notch.tab
            if let event = key("4", 21, .command) { _ = panel.performKeyEquivalent(with: event) }
            let afterFour = notch.tab
            if let event = key("\t", 48, .control) { panel.sendEvent(event) }
            report(afterOne == .terminal && afterFour == .devices && notch.tab == .terminal,
                   "⌘1 → \(afterOne), ⌘4 → \(afterFour), ⌃Tab → \(notch.tab)")
            notch.select(.devices)
            while notch.debugTabDriver.isAnimating { try? await Task.sleep(for: .milliseconds(20)) }
            report(notch.tabProgress == 3 && notch.pager.pages.count == 4, "four pages, Devices at index \(notch.tabProgress)")

            // 5. Open: connecting doesn't peek (the tab updates instead); disconnect → last seen.
            store.deviceDisconnected(id: id)
            store.deviceConnected(id: id, name: "Mewo", kind: .buds, source: .mock)
            store.apply(reading(90, 88, nil, charging: true), to: id)
            report(notch.activity == nil, "reading while open → no peek")
            try? await Task.sleep(for: .milliseconds(700))
            shot("4-charging")
            store.deviceDisconnected(id: id)
            try? await Task.sleep(for: .milliseconds(700))
            report(devices.status(store.device(id)!) == "Last seen just now", "disconnected → \"\(devices.status(store.device(id)!))\"")
            report(store.device(id)?.component(.left)?.level == 90, "values kept after disconnect")
            shot("5-disconnected")

            // 6. Close and reopen on Devices (the liquid effect pictures the tab).
            notch.close()
            _ = await notch.waitForRest()
            notch.open()
            _ = await notch.waitForRest()
            report(notch.state == .open && notch.tab == .devices, "close + reopen on Devices")
            notch.close()
            _ = await notch.waitForRest()
            store.forget(id)
            try? await Task.sleep(for: .milliseconds(300))
            report(store.device(id) == nil, "forget → gone")
            if store.devices.isEmpty {
                notch.open()
                _ = await notch.waitForRest()
                try? await Task.sleep(for: .milliseconds(500))
                shot("6-empty")
                notch.close()
                _ = await notch.waitForRest()
            }
            notch.select(.terminal)
            store.saveNow()
            print("[devices] done: \(failures) failure(s)")
            NSApp.terminate(nil)
        }
    }
}
#endif
