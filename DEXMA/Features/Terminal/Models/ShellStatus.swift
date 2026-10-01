import Observation

/// What the band shows about the shell: its working directory and whether a command is
/// running in the foreground (see `ShellSession.refreshStatus`).
@Observable
final class ShellStatus {
    /// Absolute path; empty until first read.
    var directory = ""
    /// A command (not the idle prompt) owns the terminal.
    var isRunningCommand = false
}
