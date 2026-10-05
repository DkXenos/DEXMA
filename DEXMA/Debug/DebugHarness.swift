#if DEBUG
import AppKit

/// Debug-only launch arguments that check the running app, print what they find and quit:
/// `-selftest`, `-snapshot <dir>`, `-effecttest <dir>`, `-tabtest <dir>`, `-swipetest <dir>`,
/// `-hovertest <dir>`, `-capturetest <dir>`, `-devicetest <dir>`,
/// `-warptest <dir>`, `-captureidle <s>`, `-glasstest <dir>`, `-glassprobe <dir>`, `-spotlightmeasure <dir>`.
enum DebugHarness {
    private static let flags = ["-selftest", "-captureidle", "-warptest", "-sizetest", "-captureorient", "-capturetest",
                                "-claudeprobe", "-swipetest", "-bandshot", "-hovertest", "-tabtest", "-effecttest",
                                "-snapshot", "-devicetest", "-budsprobe", "-glassprobe", "-spotlightmeasure", "-glasstest"]

    /// A harness run: the app leaves Bluetooth alone (no permission prompt mid-test);
    /// `-devicetest` starts the Buds monitor itself.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains { flags.contains($0) }
    }

    static func runIfRequested(coordinator: AppCoordinator, panel: NotchPanel, notch: NotchViewModel,
                               session: ShellSession) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        setvbuf(stdout, nil, _IOLBF, 0)  // Line-buffered, so a killed test run keeps its output.
        if arguments.contains("-budsprobe") {
            BudsProbe.run()
        } else if arguments.contains("-selftest") {
            SelfTest.run(coordinator: coordinator, panel: panel, notch: notch, session: session)
        } else if let seconds = value(after: "-captureidle") {
            WarpTest.keepCapturing(notch: notch, seconds: Double(seconds) ?? 20)
        } else if let dir = value(after: "-warptest") {
            WarpTest.run(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-sizetest") {
            SizeTest.run(coordinator: coordinator, panel: panel, notch: notch, session: session,
                         dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-captureorient") {
            CaptureTest.orientation(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-capturetest") {
            CaptureTest.run(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-claudeprobe") {
            ClaudeProbe.run(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-swipetest") {
            SwipeTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-bandshot") {
            HoverTest.shot(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-hovertest") {
            HoverTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-tabtest") {
            TabTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-effecttest") {
            EffectTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-devicetest") {
            DeviceTest.run(panel: panel, notch: notch, startMonitor: { coordinator.debugStartBudsMonitor() },
                           dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-glasstest"), let glass = coordinator.debugClaudeGlass,
                  let capture = coordinator.debugCapture {
            GlassTest.run(glass: glass, notch: notch, capture: capture, settings: coordinator.settings,
                          dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-spotlightmeasure") {
            SpotlightMeasure.run(dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-glassprobe") {
            GlassProbe.run(notch: notch, dir: URL(fileURLWithPath: dir))
        } else if let dir = value(after: "-snapshot") {
            SnapshotTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        }
    }
}
#endif
