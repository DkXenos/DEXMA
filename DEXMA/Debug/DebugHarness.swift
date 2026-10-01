#if DEBUG
import AppKit

/// Debug-only launch arguments that check the running app, print what they find and quit:
/// `-selftest`, `-snapshot <dir>`, `-effecttest <dir>`, `-tabtest <dir>`, `-swipetest <dir>`,
/// `-hovertest <dir>`,
/// `-warptest <dir>`, `-captureidle <s>`.
enum DebugHarness {
    static func runIfRequested(coordinator: AppCoordinator, panel: NotchPanel, notch: NotchViewModel,
                               session: ShellSession) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        setvbuf(stdout, nil, _IOLBF, 0)  // Line-buffered, so a killed test run keeps its output.
        if arguments.contains("-selftest") {
            SelfTest.run(coordinator: coordinator, panel: panel, notch: notch, session: session)
        } else if let seconds = value(after: "-captureidle") {
            WarpTest.keepCapturing(notch: notch, seconds: Double(seconds) ?? 20)
        } else if let dir = value(after: "-warptest") {
            WarpTest.run(panel: panel, notch: notch, dir: URL(fileURLWithPath: dir))
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
        } else if let dir = value(after: "-snapshot") {
            SnapshotTest.run(panel: panel, notch: notch, session: session, dir: URL(fileURLWithPath: dir))
        }
    }
}
#endif
