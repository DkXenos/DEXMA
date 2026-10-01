/// How a capture went into claude.ai's message box, in the order they're tried.
nonisolated enum ClaudeInsertMethod: String, Sendable {
    /// A real paste (⌘V's path) with the PNG on the clipboard, the user's clipboard restored after.
    case paste
    /// The composer's file input, given the file through a DataTransfer.
    case fileInput
    /// A scripted paste (or drop) event carrying the file.
    case syntheticEvent
}
